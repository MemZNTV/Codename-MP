// End-to-end test for the versus server: spawns it and plays fake clients through lobbies and whole matches.
//   node test/flow-test.js
'use strict';

const { spawn } = require('child_process');
const net = require('net');
const path = require('path');
const assert = require('assert');

const BASE_PORT = 17000 + Math.floor(Math.random() * 900);
const PROTOCOL = 2;
let failures = 0;

function check(name, fn) {
	try { fn(); console.log('  ok   -', name); }
	catch (e) { failures++; console.log('  FAIL -', name, '\n        ', e.message); }
}

class Bot {
	constructor(name, port) {
		this.name = name;
		this.port = port;
		this.msgs = [];
		this.waiters = [];
		this.closed = false;
		this.buf = '';
	}
	connect() {
		return new Promise((res, rej) => {
			this.sock = net.connect(this.port, '127.0.0.1', res);
			this.sock.setEncoding('utf8');
			this.sock.on('error', rej);
			this.sock.on('close', () => { this.closed = true; this.flush(); });
			this.sock.on('data', d => {
				this.buf += d;
				let i;
				while ((i = this.buf.indexOf('\n')) !== -1) {
					const line = this.buf.slice(0, i); this.buf = this.buf.slice(i + 1);
					if (line) { this.msgs.push(JSON.parse(line)); this.flush(); }
				}
			});
		});
	}
	send(o) { this.sock.write(JSON.stringify(o) + '\n'); }
	flush() {
		for (const w of [...this.waiters]) {
			const i = this.msgs.findIndex(w.pred);
			if (i !== -1) { this.waiters.splice(this.waiters.indexOf(w), 1); w.res(this.msgs.splice(i, 1)[0]); }
			else if (this.closed) { this.waiters.splice(this.waiters.indexOf(w), 1); w.rej(new Error(`${this.name}: closed while waiting for ${w.desc}`)); }
		}
	}
	// Wait for a message matching pred (consumes it).
	wait(desc, pred, ms = 3000) {
		return new Promise((res, rej) => {
			const w = { pred, res, rej, desc };
			this.waiters.push(w);
			this.flush();
			setTimeout(() => {
				const i = this.waiters.indexOf(w);
				if (i !== -1) { this.waiters.splice(i, 1); rej(new Error(`${this.name}: timeout waiting for ${desc}`)); }
			}, ms);
		});
	}
	// Room / lobby-list snapshots arrive many times; skip until one matches.
	async waitKind(kind, desc, pred) {
		for (let n = 0; n < 30; n++) {
			const r = await this.wait(`${kind}:${desc}`, m => m.t === kind);
			if (pred(r)) return r;
		}
		throw new Error(`${this.name}: ${kind} never matched ${desc}`);
	}
	waitRoom(desc, pred) { return this.waitKind('room', desc, pred); }
	waitLobbies(desc, pred) { return this.waitKind('lobbies', desc, pred); }
	silent(ms) { return new Promise(r => setTimeout(r, ms)); }
}

async function startServer(port, extraArgs = []) {
	const server = spawn(process.execPath, [path.join(__dirname, '..', 'server.js'), '--port', String(port), '--host', '127.0.0.1', '--roll-ms', '300', ...extraArgs], { stdio: ['ignore', 'pipe', 'inherit'] });
	await new Promise((res, rej) => { server.stdout.on('data', d => { if (String(d).includes('listening')) res(); }); server.on('exit', c => rej(new Error('server exited ' + c))); });
	return server;
}

async function login(port, name, extra = {}) {
	const b = new Bot(name, port);
	await b.connect();
	b.send({ t: 'hello', v: PROTOCOL, name, mod: 'mymod', ...extra });
	b.welcome = await b.wait('welcome', m => m.t === 'welcome');
	return b;
}

// Two logged-in bots in one open lobby.
async function pair(port, n) {
	const x = await login(port, 'P1_' + n), y = await login(port, 'P2_' + n);
	x.send({ t: 'create' });
	const joined = await x.wait('joined', m => m.t === 'joined');
	y.send({ t: 'join', id: joined.id });
	await y.wait('joined', m => m.t === 'joined');
	return [x, y, joined.id];
}

async function main() {
	const PORT = BASE_PORT;
	const server = await startServer(PORT);
	console.log('server up on', PORT);
	const cleanupBots = [];

	try {
		// ------------------------------------------------ usernames + lobby browser
		const a = await login(PORT, 'Alice');
		cleanupBots.push(a);
		check('alice welcomed with her name', () => assert.strictEqual(a.welcome.name, 'Alice'));
		const empty = await a.wait('lobbies', m => m.t === 'lobbies');
		check('lobby list starts empty', () => assert.strictEqual(empty.lobbies.length, 0));

		const dupe = await login(PORT, 'alice', { mod: 'othermod' }); // same name, different case
		cleanupBots.push(dupe);
		check('duplicate username gets a unique suffix', () => assert.strictEqual(dupe.welcome.name, 'alice (2)'));

		const b = dupe; // "alice (2)" plays as the second player below
		const c = await login(PORT, 'Carol'); cleanupBots.push(c);

		// ------------------------------------------------ create a locked lobby
		a.send({ t: 'create', password: 'secret' });
		const joinedA = await a.wait('joined', m => m.t === 'joined');
		let room = await a.waitRoom('a alone', r => r.players.length === 1);
		check('lobby is titled after the host\'s mod', () => assert.strictEqual(room.title, 'mymod'));
		check('lobby reports it is locked', () => assert.strictEqual(room.locked, true));

		const list = await b.waitLobbies('sees lobby', l => l.lobbies.length === 1);
		check('browsing players see the lobby (title, host, lock)', () => {
			const l = list.lobbies[0];
			assert.strictEqual(l.title, 'mymod'); assert.strictEqual(l.host, 'Alice'); assert.strictEqual(l.locked, true);
			assert.strictEqual(l.players, 1); assert.strictEqual(l.id, joinedA.id);
		});
		check('the password itself is never sent to clients', () => assert.ok(!JSON.stringify(list).includes('secret') && !JSON.stringify(room).includes('secret')));

		// ------------------------------------------------ lobby password
		b.send({ t: 'join', id: joinedA.id, password: 'wrong' });
		const badPw = await b.wait('lobby_password', m => m.t === 'error');
		check('wrong lobby password is refused (connection stays open)', () => { assert.strictEqual(badPw.code, 'lobby_password'); assert.ok(!badPw.fatal); });
		b.send({ t: 'join', id: 99999 });
		const gone = await b.wait('no_lobby', m => m.t === 'error');
		check('joining a non-existent lobby fails politely', () => assert.strictEqual(gone.code, 'no_lobby'));
		b.send({ t: 'join', id: joinedA.id, password: 'secret' });
		await b.wait('joined', m => m.t === 'joined');
		room = await a.waitRoom('2 players', r => r.players.length === 2);
		check('correct password lets the second player in', () => assert.strictEqual(room.players.length, 2));

		c.send({ t: 'join', id: joinedA.id, password: 'secret' });
		const full = await c.wait('lobby_full', m => m.t === 'error');
		check('a third player gets lobby_full', () => assert.strictEqual(full.code, 'lobby_full'));

		// ------------------------------------------------ clock sync
		a.send({ t: 'ping', c: 123 });
		const pong = await a.wait('pong', m => m.t === 'pong');
		check('pong echoes client stamp + server time', () => { assert.strictEqual(pong.c, 123); assert.ok(Math.abs(pong.s - Date.now()) < 1000); });

		// ------------------------------------------------ sides
		a.send({ t: 'side', side: 'left' });
		b.send({ t: 'side', side: 'left' });
		const sideErr = await b.wait('side_taken', m => m.t === 'error');
		check('same side rejected', () => assert.strictEqual(sideErr.code, 'side_taken'));
		b.send({ t: 'side', side: 'right' });
		room = await a.waitRoom('both sides', r => r.players.every(p => p.side));
		check('sides assigned', () => assert.deepStrictEqual(room.players.map(p => p.side), ['left', 'right']));

		// ------------------------------------------------ song picks + ready + roll
		a.send({ t: 'song', name: 'bopeebo', diff: 'hard', variant: null, display: 'Bopeebo', hash: 'abc123' });
		b.send({ t: 'song', name: 'fresh', diff: 'normal', variant: null, display: 'Fresh', hash: 'def456' });
		room = await b.waitRoom('both picked', r => r.players.every(p => p.pick));
		check('each player has their own pick', () => { assert.strictEqual(room.players[0].pick.name, 'bopeebo'); assert.strictEqual(room.players[1].pick.name, 'fresh'); });

		a.send({ t: 'ready', ready: true });
		await a.waitRoom('alice ready', r => r.players[0].ready);
		await a.silent(100);
		check('no roll with only one player ready', () => assert.ok(!a.msgs.some(m => m.t === 'roll')));
		b.send({ t: 'ready', ready: true });

		const rollA = await a.wait('roll', m => m.t === 'roll');
		const rollB = await b.wait('roll', m => m.t === 'roll');
		check('both get the same roll (2 options, same winner)', () => {
			assert.strictEqual(rollA.options.length, 2);
			assert.deepStrictEqual(rollA.options.map(o => o.name), ['bopeebo', 'fresh']);
			assert.strictEqual(rollA.chosen, rollB.chosen);
			assert.strictEqual(rollA.options[0].by, 'Alice');
		});
		const loadA = await a.wait('load', m => m.t === 'load');
		const loadB = await b.wait('load', m => m.t === 'load');
		check('load carries the rolled song for both', () => {
			assert.strictEqual(loadA.song.name, rollA.options[rollA.chosen].name);
			assert.deepStrictEqual(loadA.song, loadB.song);
		});

		// ------------------------------------------------ synchronized start + relay
		a.send({ t: 'loaded' }); b.send({ t: 'loaded' });
		const sA = await a.wait('start', m => m.t === 'start');
		const sB = await b.wait('start', m => m.t === 'start');
		check('both get the same start time', () => { assert.strictEqual(sA.at, sB.at); assert.ok(sA.at > Date.now() - 500); });

		a.send({ t: 'g', k: 'h', l: 2, m: 1234.5, d: 12 });
		const relayed = await b.wait('relayed hit', m => m.t === 'g');
		check('hit relayed to opponent', () => { assert.strictEqual(relayed.k, 'h'); assert.strictEqual(relayed.l, 2); });
		await a.silent(100);
		check('sender does not get its own event', () => assert.ok(!a.msgs.some(m => m.t === 'g')));

		// ------------------------------------------------ results
		a.send({ t: 'result', score: 9000, misses: 3, accuracy: 91.5, maxCombo: 40, hits: { sick: 50, good: 5 } });
		await a.silent(100);
		check('no results until both report', () => assert.ok(!a.msgs.some(m => m.t === 'results')));
		b.send({ t: 'result', score: 12000, misses: 1, accuracy: 96.2, maxCombo: 80, hits: { sick: 70 } });
		const resA = await a.wait('results', m => m.t === 'results');
		const resB = await b.wait('results', m => m.t === 'results');
		check('results contain both players', () => { assert.strictEqual(Object.keys(resA.players).length, 2); assert.strictEqual(resA.players[b.welcome.id].score, 12000); assert.strictEqual(resB.players[a.welcome.id].hits.sick, 50); });
		room = await a.waitRoom('back to lobby', r => r.state === 'lobby' && r.players.every(p => !p.ready));
		check('room reset to lobby with ready cleared', () => assert.strictEqual(room.state, 'lobby'));

		// ------------------------------------------------ second match: identical picks -> single option
		a.send({ t: 'song', name: 'dadbattle', diff: 'hard', variant: null, display: 'Dad Battle', hash: 'x1' });
		b.send({ t: 'song', name: 'dadbattle', diff: 'hard', variant: null, display: 'Dad Battle', hash: 'x1' });
		await b.waitRoom('picks updated', r => r.players.every(p => p.pick && p.pick.name === 'dadbattle'));
		a.send({ t: 'ready', ready: true }); b.send({ t: 'ready', ready: true });
		const same = await a.wait('same roll', m => m.t === 'roll');
		check('identical picks give a single option', () => assert.strictEqual(same.options.length, 1));
		await a.wait('load2', m => m.t === 'load'); await b.wait('load2', m => m.t === 'load');
		a.send({ t: 'loaded' }); b.send({ t: 'loaded' });
		await a.wait('start2', m => m.t === 'start'); await b.wait('start2', m => m.t === 'start');

		// ------------------------------------------------ forfeit mid-match via leave_lobby; host + title hand over
		a.send({ t: 'leave_lobby' });
		const left = await b.wait('opp_left', m => m.t === 'opp_left');
		check('opponent told when a player leaves mid-match', () => assert.strictEqual(left.id, a.welcome.id));
		const aLobbies = await a.wait('lobbies after leave', m => m.t === 'lobbies');
		check('leaver is back at the lobby list, still connected', () => assert.strictEqual(aLobbies.lobbies.length, 1));
		room = await b.waitRoom('bob alone', r => r.players.length === 1);
		check('remaining player becomes host and the title follows THEIR mod', () => { assert.strictEqual(room.state, 'lobby'); assert.strictEqual(room.host, b.welcome.id); assert.strictEqual(room.title, 'othermod'); });
		const relisted = await a.waitLobbies('title changed', l => l.lobbies.length === 1 && l.lobbies[0].title === 'othermod');
		check('lobby list shows the new title and host', () => assert.strictEqual(relisted.lobbies[0].host, 'alice (2)'));

		// ------------------------------------------------ closing an empty lobby removes it from the list
		b.send({ t: 'leave_lobby' });
		const none = await a.waitLobbies('empty again', l => l.lobbies.length === 0);
		check('empty lobbies disappear from the list', () => assert.strictEqual(none.lobbies.length, 0));

		// ------------------------------------------------ leaving during the roll cancels it
		{
			const [c1, c2] = await pair(PORT, 'roll'); cleanupBots.push(c1, c2);
			c1.send({ t: 'side', side: 'left' }); c2.send({ t: 'side', side: 'right' });
			c1.send({ t: 'song', name: 'a', diff: 'x' }); c2.send({ t: 'song', name: 'b', diff: 'x' });
			await c2.waitRoom('picks', r => r.players.every(p => p.side && p.pick));
			c1.send({ t: 'ready', ready: true }); c2.send({ t: 'ready', ready: true });
			await c2.wait('roll', m => m.t === 'roll');
			c1.sock.destroy();
			const ab = await c2.wait('abort', m => m.t === 'abort');
			check('leaving mid-roll aborts for the other player', () => assert.strictEqual(ab.code, 'opp_left'));
			const r2 = await c2.waitRoom('back in lobby', r => r.state === 'lobby' && r.players.length === 1);
			check('room is back in lobby after abort', () => assert.strictEqual(r2.state, 'lobby'));
		}

		// ------------------------------------------------ roll fairness
		{
			const wins = [0, 0];
			for (let n = 0; n < 30; n++) {
				const [p1, p2] = await pair(PORT, 'fair' + n);
				p1.send({ t: 'side', side: 'left' }); p2.send({ t: 'side', side: 'right' });
				p1.send({ t: 'song', name: 'a', diff: 'x' }); p2.send({ t: 'song', name: 'b', diff: 'x' });
				await p2.waitRoom('ready-up', r => r.players.every(p => p.side && p.pick));
				p1.send({ t: 'ready', ready: true }); p2.send({ t: 'ready', ready: true });
				const r = await p1.wait('roll', m => m.t === 'roll');
				wins[r.chosen]++;
				p1.sock.destroy(); p2.sock.destroy();
			}
			check(`roll is not stuck on one option (${wins[0]} vs ${wins[1]} of 30)`, () => assert.ok(wins[0] >= 4 && wins[1] >= 4));
		}

		// ------------------------------------------------ robustness
		{
			const d = new Bot('Dave', PORT); await d.connect(); cleanupBots.push(d);
			d.sock.write('this is not json\n{"t":"hello"\n\n');
			d.send({ t: 'hello', v: PROTOCOL, name: 'x'.repeat(500), mod: 'm'.repeat(500) });
			const wd = await d.wait('welcome after garbage', m => m.t === 'welcome');
			check('garbage tolerated; long name is cut to 20 chars', () => assert.ok(wd.name.length <= 20));
			d.send({ t: 'create' });
			const jd = await d.wait('joined', m => m.t === 'joined');
			room = await d.waitRoom('dave alone', r => r.players.length === 1);
			check('over-long mod name is truncated in the lobby title', () => assert.ok(room.title.length <= 40 && jd.id > 0));
		}
		{
			const e = new Bot('Eve', PORT); await e.connect(); cleanupBots.push(e);
			e.send({ t: 'hello', v: 999, name: 'eve' });
			const ver = await e.wait('version error', m => m.t === 'error');
			check('wrong protocol version refused (fatal)', () => { assert.strictEqual(ver.code, 'version'); assert.ok(ver.fatal); });
		}
	} finally {
		cleanupBots.forEach(x => { try { x.sock.destroy(); } catch (_) {} });
		server.kill();
	}

	// ------------------------------------------------ optional server-wide password
	const PORT2 = BASE_PORT + 1;
	const server2 = await startServer(PORT2, ['--password', 'hunter2']);
	try {
		const bad = new Bot('Mallory', PORT2); await bad.connect();
		bad.send({ t: 'hello', v: PROTOCOL, name: 'mallory', pass: 'nope' });
		const e1 = await bad.wait('bad_password', m => m.t === 'error');
		check('server password: wrong one is refused (fatal)', () => { assert.strictEqual(e1.code, 'bad_password'); assert.ok(e1.fatal); });
		const good = await login(PORT2, 'Trudy', { pass: 'hunter2' });
		check('server password: correct one is welcomed', () => assert.strictEqual(good.welcome.name, 'Trudy'));
		good.sock.destroy(); bad.sock.destroy();
	} finally {
		server2.kill();
	}

	console.log(failures === 0 ? '\nAll checks passed.' : `\n${failures} check(s) FAILED.`);
	process.exit(failures === 0 ? 0 : 1);
}

main().catch(e => { console.error('TEST ERROR:', e.message); process.exit(2); });
