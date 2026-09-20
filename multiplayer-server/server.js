#!/usr/bin/env node
/**
 * Codename Engine - Versus Multiplayer Server
 *
 * A tiny lobby + relay server. It does NOT simulate the game: each client plays its own
 * copy of the song locally and this server only
 *   - keeps a list of open lobbies (titled after the mod their host is playing, optionally password protected),
 *   - pairs two players in a lobby and tracks side (left/right), each player's song pick and ready state,
 *   - when both are ready, randomly rolls between the two picks,
 *   - hands out a shared start time so both songs begin together,
 *   - forwards in-game events (key presses, hits, misses, stats) between the two players,
 *   - collects the final results of both players.
 *
 * Zero dependencies. Requires Node.js 16+.
 *
 *   node server.js [--port 7777] [--host 0.0.0.0] [--password secret]
 *
 * --password is an optional password for the whole SERVER (nobody can connect without it).
 * Individual lobbies can additionally have their own password, chosen by whoever creates them.
 *
 * Protocol: TCP, one JSON object per line (UTF-8, "\n" terminated). See PROTOCOL.md.
 */
'use strict';

const net = require('net');
const crypto = require('crypto');

// ------------------------------------------------------------------ config

function arg(name, fallback) {
	const i = process.argv.indexOf('--' + name);
	return i !== -1 && i + 1 < process.argv.length ? process.argv[i + 1] : fallback;
}

const PORT = parseInt(arg('port', process.env.PORT || '7777'), 10);
const HOST = arg('host', process.env.HOST || '0.0.0.0');
const SERVER_PASSWORD = arg('password', process.env.AFTERNIGHT_PASSWORD || '');

const PROTOCOL_VERSION = 2;
const MAX_LINE_BYTES = 16 * 1024;       // a single message can never be bigger than this
const MAX_CLIENTS = 64;                 // total simultaneous connections
const MAX_CLIENTS_PER_IP = 8;
const MAX_LOBBIES = 32;
const MAX_MSGS_PER_SEC = 300;           // flood protection (a real client sends < 100/s)
const HELLO_TIMEOUT_MS = 10000;         // must say hello quickly or get dropped
const IDLE_TIMEOUT_MS = 30000;          // clients ping every ~2s, silence for this long = dead
const LOAD_TIMEOUT_MS = 45000;          // max time to wait for both players to finish loading
const START_DELAY_MS = 1200;            // shared start time = now + this (covers network jitter)
const MAX_PLAYERS = 2;
const ROLL_MS = parseInt(arg('roll-ms', process.env.ROLL_MS || '3800'), 10);    // length of the song roll animation
const ROLL_SAME_MS = Math.min(ROLL_MS, 1400);                                    // both picked the same song: no suspense needed
const ROLL_GRACE_MS = 600;                                                       // clients finish animating a bit after 'ms'

// ------------------------------------------------------------------ helpers

const now = () => Date.now();

function log(...a) {
	const d = new Date();
	const ts = d.toTimeString().slice(0, 8);
	console.log(`[${ts}]`, ...a);
}

function cleanName(s) {
	s = String(s == null ? '' : s).replace(/[^\x20-\x7E]/g, '').trim();
	return s.slice(0, 20) || 'Player';
}

function cleanStr(s, max) {
	return String(s == null ? '' : s).replace(/[\x00-\x1F]/g, '').slice(0, max);
}

function num(n, def = 0) {
	n = Number(n);
	return Number.isFinite(n) ? n : def;
}

// Constant-time-ish password comparison (avoids leaking the length/prefix through timing).
function passwordMatches(given, expected) {
	const a = crypto.createHash('sha256').update(String(given == null ? '' : given)).digest();
	const b = crypto.createHash('sha256').update(String(expected)).digest();
	return crypto.timingSafeEqual(a, b);
}

// ------------------------------------------------------------------ state

let nextClientId = 1;
let nextRoomId = 1;
const clients = new Set();
const rooms = new Map(); // id -> Room

/** Sends the current lobby list to everyone who is looking at it (connected but not inside a lobby). */
function pushLobbyList() {
	const lobbies = lobbyList();
	const line = JSON.stringify({ t: 'lobbies', lobbies }) + '\n';
	for (const c of clients) if (c.authed && !c.room) c.raw(line);
}

function lobbyList() {
	return [...rooms.values()].map(r => ({
		id: r.id,
		title: r.title,
		host: r.host ? r.host.name : '?',
		players: r.players.length,
		max: MAX_PLAYERS,
		locked: !!r.password,
		state: r.state,
	}));
}

class Room {
	constructor(password) {
		this.id = nextRoomId++;
		this.password = password;   // '' = open lobby
		this.players = [];          // Client[] (max 2, join order; players[0] is the host)
		this.state = 'lobby';       // lobby | rolling | loading | playing
		this.song = null;           // the rolled song of the current match: { name, diff, variant, display, hash, by }
		this.rollTimer = null;
		this.loadTimer = null;
		this.results = new Map();   // clientId -> result object
	}

	get host() { return this.players[0] || null; }

	// The lobby is named after the mod its host is playing.
	get title() {
		const m = this.host ? this.host.mod : '';
		return m || 'Base game';
	}

	snapshot() {
		return {
			t: 'room',
			id: this.id,
			title: this.title,
			locked: !!this.password,
			state: this.state,
			host: this.host ? this.host.id : 0,
			song: this.song,
			players: this.players.map(p => ({
				id: p.id,
				name: p.name,
				side: p.side,
				ready: p.ready,
				pick: p.pick,
				mod: p.mod,
				ping: p.ping,
			})),
		};
	}

	broadcast(obj, except) {
		const line = JSON.stringify(obj) + '\n';
		for (const p of this.players) if (p !== except) p.raw(line);
	}

	broadcastRoom() { this.broadcast(this.snapshot()); }

	resetReady() { for (const p of this.players) p.ready = false; }

	setState(state) {
		this.state = state;
		pushLobbyList();
	}

	canStart() {
		if (this.state !== 'lobby' || this.players.length !== MAX_PLAYERS) return false;
		const [a, b] = this.players;
		return a.ready && b.ready && a.pick && b.pick && a.side && b.side && a.side !== b.side;
	}

	// Both players are ready: pick one of the two songs at random and tell everyone (they animate the roll).
	tryStart() {
		if (!this.canStart()) return;
		const [a, b] = this.players;
		const sameSong = a.pick.name === b.pick.name && a.pick.diff === b.pick.diff && a.pick.variant === b.pick.variant;
		const options = sameSong
			? [{ ...a.pick, by: a.name }]
			: [{ ...a.pick, by: a.name }, { ...b.pick, by: b.name }];
		const chosen = options.length === 1 ? 0 : crypto.randomInt(options.length);
		this.song = options[chosen];
		this.setState('rolling');
		this.results.clear();
		const ms = sameSong ? ROLL_SAME_MS : ROLL_MS;
		log(`lobby #${this.id}: rolling ${options.map(o => `"${o.name}"`).join(' vs ')} -> "${this.song.name}"`);
		this.broadcast({ t: 'roll', options, chosen, ms });
		this.broadcastRoom();
		clearTimeout(this.rollTimer);
		this.rollTimer = setTimeout(() => { if (this.state === 'rolling') this.startLoading(); }, ms + ROLL_GRACE_MS);
	}

	startLoading() {
		this.setState('loading');
		for (const p of this.players) p.loaded = false;
		log(`lobby #${this.id}: loading "${this.song.name}" (${this.song.diff})`);
		this.broadcast({ t: 'load', song: this.song });
		this.broadcastRoom();
		clearTimeout(this.loadTimer);
		this.loadTimer = setTimeout(() => {
			if (this.state === 'loading') {
				log(`lobby #${this.id}: load timeout`);
				this.abort('load_timeout', 'A player took too long to load the song.');
			}
		}, LOAD_TIMEOUT_MS);
	}

	// A player finished creating PlayState.
	markLoaded(p) {
		if (this.state !== 'loading') return;
		p.loaded = true;
		if (this.players.length === MAX_PLAYERS && this.players.every(x => x.loaded)) {
			clearTimeout(this.loadTimer);
			this.setState('playing');
			const at = now() + START_DELAY_MS;
			log(`lobby #${this.id}: go!`);
			this.broadcast({ t: 'start', at });
			this.broadcastRoom();
		}
	}

	// Cancel a match in progress and send everyone back to the lobby.
	abort(code, msg) {
		clearTimeout(this.loadTimer);
		clearTimeout(this.rollTimer);
		this.setState('lobby');
		this.results.clear();
		this.resetReady();
		this.broadcast({ t: 'abort', code, msg });
		this.broadcastRoom();
	}

	submitResult(p, r) {
		if (this.state !== 'playing') return;
		this.results.set(p.id, r);
		if (this.players.length === MAX_PLAYERS && this.players.every(x => this.results.has(x.id))) {
			const out = {};
			for (const x of this.players) out[x.id] = { name: x.name, side: x.side, ...this.results.get(x.id) };
			log(`lobby #${this.id}: match finished`);
			this.setState('lobby');
			this.resetReady();
			this.results.clear();
			this.broadcast({ t: 'results', players: out });
			this.broadcastRoom();
		}
	}

	add(p) {
		this.players.push(p);
		p.room = this;
		p.side = null;
		p.pick = null;
		p.ready = false;
		this.resetReady();
	}

	remove(p, reason) {
		const i = this.players.indexOf(p);
		if (i === -1) return;
		const prevState = this.state;
		this.players.splice(i, 1);
		p.room = null;
		p.side = null;
		p.pick = null;
		p.ready = false;

		clearTimeout(this.loadTimer);
		clearTimeout(this.rollTimer);

		if (this.players.length === 0) {
			rooms.delete(this.id);
			log(`lobby #${this.id}: closed`);
			pushLobbyList();
			return;
		}

		this.state = 'lobby';
		this.results.clear();
		this.resetReady();
		if (prevState === 'playing') {
			// The remaining player is told before the room resets so they can show a proper screen.
			this.broadcast({ t: 'opp_left', id: p.id, name: p.name, reason });
		} else if (prevState === 'rolling' || prevState === 'loading') {
			// the match never really started: just cancel it
			this.broadcast({ t: 'abort', code: 'opp_left', msg: `${p.name} left before the match started.` });
		}
		this.broadcastRoom();
		pushLobbyList(); // the host (and so the title) may have changed
	}
}

// ------------------------------------------------------------------ client

class Client {
	constructor(socket) {
		this.socket = socket;
		this.id = nextClientId++;
		this.ip = socket.remoteAddress || '?';
		this.buf = '';
		this.name = 'Player';
		this.mod = '';
		this.room = null;
		this.side = null;
		this.pick = null;       // the song this player wants: { name, diff, variant, display, hash }
		this.ready = false;
		this.loaded = false;
		this.ping = 0;
		this.authed = false;
		this.closed = false;
		this.msgCount = 0;
		this.msgWindow = now();
		this.lastSeen = now();
	}

	raw(line) {
		if (this.closed) return;
		try { this.socket.write(line); } catch (e) { /* socket errors are handled by 'error'/'close' */ }
	}

	send(obj) { this.raw(JSON.stringify(obj) + '\n'); }

	error(code, msg, fatal) {
		this.send({ t: 'error', code, msg, fatal: !!fatal });
		if (fatal) this.close();
	}

	close() {
		if (this.closed) return;
		this.closed = true;
		try { this.socket.end(); } catch (e) {}
		setTimeout(() => { try { this.socket.destroy(); } catch (e) {} }, 500);
	}
}

// Usernames are unique on a server ("Bob" taken -> "Bob (2)").
function uniqueName(base) {
	const taken = new Set();
	for (const c of clients) if (c.authed) taken.add(c.name.toLowerCase());
	if (!taken.has(base.toLowerCase())) return base;
	for (let n = 2; n < 100; n++) {
		const suffix = ` (${n})`;
		const candidate = base.slice(0, 20 - suffix.length) + suffix;
		if (!taken.has(candidate.toLowerCase())) return candidate;
	}
	return base.slice(0, 14) + ' #' + nextClientId;
}

// ------------------------------------------------------------------ message handling

function handle(c, m) {
	if (!m || typeof m !== 'object' || typeof m.t !== 'string') return;

	if (m.t === 'ping') {
		// Also serves as the keep-alive. Reply with server clock for time sync.
		if (typeof m.p === 'number') c.ping = Math.max(0, Math.min(9999, Math.round(m.p))); // client-measured RTT
		c.send({ t: 'pong', c: num(m.c), s: now() });
		return;
	}

	if (!c.authed) {
		if (m.t !== 'hello') return c.error('protocol', 'Expected hello.', true);
		if (num(m.v) !== PROTOCOL_VERSION) return c.error('version', `Protocol mismatch (server ${PROTOCOL_VERSION}). Update your game/server.`, true);
		if (SERVER_PASSWORD && !passwordMatches(m.pass, SERVER_PASSWORD)) return c.error('bad_password', 'Wrong server password.', true);

		c.name = uniqueName(cleanName(m.name));
		c.mod = cleanStr(m.mod, 40);
		c.authed = true;
		log(`#${c.id} "${c.name}" (${c.ip}) connected, mod "${c.mod || 'base'}"`);
		c.send({ t: 'welcome', id: c.id, name: c.name, v: PROTOCOL_VERSION, serverTime: now() });
		c.send({ t: 'lobbies', lobbies: lobbyList() });
		return;
	}

	// ---- lobby browser (not inside a lobby yet)
	switch (m.t) {
		case 'lobbies':
			return c.send({ t: 'lobbies', lobbies: lobbyList() });

		case 'create': {
			if (c.room) return;
			if (rooms.size >= MAX_LOBBIES) return c.error('too_many_lobbies', 'The server has too many lobbies right now.');
			if (typeof m.mod === 'string') c.mod = cleanStr(m.mod, 40); // the mod can change between menu visits
			const room = new Room(cleanStr(m.password, 32));
			rooms.set(room.id, room);
			room.add(c);
			log(`lobby #${room.id} "${room.title}" created by "${c.name}"${room.password ? ' (locked)' : ''}`);
			c.send({ t: 'joined', id: room.id });
			room.broadcastRoom();
			pushLobbyList();
			return;
		}

		case 'join': {
			if (c.room) return;
			const room = rooms.get(num(m.id, -1));
			if (!room) { c.error('no_lobby', 'That lobby no longer exists.'); return c.send({ t: 'lobbies', lobbies: lobbyList() }); }
			if (room.players.length >= MAX_PLAYERS) return c.error('lobby_full', 'That lobby is full.');
			if (room.state !== 'lobby') return c.error('lobby_busy', 'That lobby is in the middle of a match.');
			if (room.password && !passwordMatches(m.password, room.password)) return c.error('lobby_password', 'Wrong lobby password.');
			if (typeof m.mod === 'string') c.mod = cleanStr(m.mod, 40);
			room.add(c);
			log(`#${c.id} "${c.name}" joined lobby #${room.id} [${room.players.length}/${MAX_PLAYERS}]`);
			c.send({ t: 'joined', id: room.id });
			room.broadcastRoom();
			pushLobbyList();
			return;
		}
	}

	const room = c.room;
	if (!room) return;

	// ---- inside a lobby
	switch (m.t) {
		case 'side': {
			if (room.state !== 'lobby') return;
			let side = m.side === 'left' || m.side === 'right' ? m.side : null;
			if (side && room.players.some(p => p !== c && p.side === side)) {
				c.error('side_taken', `The ${side} side is already taken.`);
				return room.broadcastRoom(); // resync the client's UI
			}
			c.side = side;
			room.resetReady();
			room.broadcastRoom();
			return;
		}

		case 'song': {
			// Every player picks a song; once both are ready the server rolls between the two picks.
			if (room.state !== 'lobby') return;
			const name = cleanStr(m.name, 80);
			if (!name) return;
			c.pick = {
				name,
				diff: cleanStr(m.diff, 40),
				variant: m.variant == null ? null : cleanStr(m.variant, 40),
				display: cleanStr(m.display || name, 80),
				hash: cleanStr(m.hash, 64),
			};
			room.resetReady();
			room.broadcastRoom();
			return;
		}

		case 'ready': {
			if (room.state !== 'lobby') return;
			c.ready = !!m.ready;
			room.broadcastRoom();
			room.tryStart();
			return;
		}

		case 'loaded':
			return room.markLoaded(c);

		case 'g': {
			// In-game event: relay untouched to the opponent. Only while a match is running.
			if (room.state !== 'loading' && room.state !== 'playing') return;
			room.broadcast(m, c);
			return;
		}

		case 'result': {
			const hits = {};
			if (m.hits && typeof m.hits === 'object') {
				for (const k of Object.keys(m.hits).slice(0, 12)) hits[cleanStr(k, 16)] = num(m.hits[k]);
			}
			room.submitResult(c, {
				score: Math.round(num(m.score)),
				misses: Math.round(num(m.misses)),
				accuracy: num(m.accuracy),
				maxCombo: Math.round(num(m.maxCombo)),
				hits,
			});
			return;
		}

		case 'leave_lobby': // back to the lobby list, staying connected (also used to forfeit a match)
			room.remove(c, 'left');
			return c.send({ t: 'lobbies', lobbies: lobbyList() });

		default:
			return;
	}
}

// ------------------------------------------------------------------ networking

const server = net.createServer(socket => {
	const ip = socket.remoteAddress || '?';
	let sameIp = 0;
	for (const c of clients) if (c.ip === ip) sameIp++;

	if (clients.size >= MAX_CLIENTS || sameIp >= MAX_CLIENTS_PER_IP) {
		socket.end(JSON.stringify({ t: 'error', code: 'busy', msg: 'Server is busy.', fatal: true }) + '\n');
		return;
	}

	socket.setNoDelay(true);
	socket.setKeepAlive(true, 10000);
	socket.setEncoding('utf8');

	const c = new Client(socket);
	clients.add(c);

	const helloTimer = setTimeout(() => {
		if (!c.authed) { c.error('timeout', 'No hello received.', true); }
	}, HELLO_TIMEOUT_MS);

	socket.on('data', chunk => {
		c.lastSeen = now();
		c.buf += chunk;

		if (c.buf.length > MAX_LINE_BYTES * 4) { c.buf = ''; return c.error('too_big', 'Message too large.', true); }

		let nl;
		while ((nl = c.buf.indexOf('\n')) !== -1) {
			const line = c.buf.slice(0, nl);
			c.buf = c.buf.slice(nl + 1);
			if (!line.trim()) continue;
			if (line.length > MAX_LINE_BYTES) return c.error('too_big', 'Message too large.', true);

			// flood protection
			const t = now();
			if (t - c.msgWindow >= 1000) { c.msgWindow = t; c.msgCount = 0; }
			if (++c.msgCount > MAX_MSGS_PER_SEC) return c.error('flood', 'Too many messages.', true);

			let msg;
			try { msg = JSON.parse(line); } catch (e) { continue; }
			try { handle(c, msg); } catch (e) { log(`handler error for #${c.id}:`, e); }
		}
	});

	const cleanup = () => {
		clearTimeout(helloTimer);
		if (!clients.delete(c)) return;
		c.closed = true;
		if (c.room) {
			log(`#${c.id} "${c.name}" left lobby #${c.room.id}`);
			c.room.remove(c, 'disconnect');
		} else if (c.authed) {
			log(`#${c.id} "${c.name}" disconnected`);
		}
	};
	socket.on('close', cleanup);
	socket.on('error', () => { /* 'close' follows */ });
});

// Drop connections that went silent (clients ping constantly, so silence = gone).
setInterval(() => {
	const t = now();
	for (const c of clients) if (t - c.lastSeen > IDLE_TIMEOUT_MS) { log(`#${c.id} timed out`); c.close(); }
}, 5000).unref();

server.on('error', e => {
	if (e.code === 'EADDRINUSE') log(`Port ${PORT} is already in use. Is another server running? Use --port to pick another.`);
	else log('Server error:', e.message);
	process.exit(1);
});

server.listen(PORT, HOST, () => {
	log(`Versus server listening on ${HOST}:${PORT}${SERVER_PASSWORD ? ' (server password required)' : ''}`);
	log('Forward this TCP port on your router to let players outside your network connect.');
});

process.on('SIGINT', () => { log('Shutting down.'); process.exit(0); });

module.exports = { server, PROTOCOL_VERSION };
