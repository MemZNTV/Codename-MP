package funkin.multiplayer;

import funkin.backend.FunkinText;
import funkin.backend.chart.ChartData.ChartMetaData;
import funkin.game.HealthIcon;
import funkin.menus.FreeplayState.FreeplaySonglist;

/**
 * Song picker for the lobby: lists the loaded mod's songs (the same list Freeplay shows) and sends the
 * chosen song + difficulty to the room as this player's pick.
 *
 * NOTE: deliberately NOT a subclass of `FreeplayState`. Many mods redirect the freeplay screen to their own
 * (with `Std.isOfType(state, FreeplayState)` checks in a global script), which also matches subclasses and
 * would swap this picker for the mod's freeplay, which starts the song by itself instead of picking it.
 */
class MultiplayerFreeplayState extends MPScreen {
	static inline final ROWS:Int = 7;
	static inline final ROW_H:Int = 66;
	static inline final LIST_Y:Int = 130;

	var songs:Array<ChartMetaData> = [];
	var icons:Array<HealthIcon> = [];

	var rowPanels:Array<FlxSprite> = [];
	var rowTexts:Array<FunkinText> = [];
	var diffText:FunkinText;
	var emptyText:FunkinText;

	var selected:Int = 0;
	var top:Int = 0; // first visible song (scrolling)

	// difficulties of the selected song (variants' difficulties are appended, like in Freeplay)
	var diffs:Array<String> = [];
	var diffKeys:Array<Null<String>> = []; // variant each difficulty belongs to (null = the song itself)
	var curDiff:Int = 0;

	public function new() {
		super(false); // no state scripts: a mod's script could start songs on its own
	}

	override function screenTitle():String
		return "PICK YOUR SONG";

	override function create() {
		super.create();

		songs = [for (s in FreeplaySonglist.get().songs) if (s != null) s];

		for (i in 0...ROWS) {
			var y = LIST_Y + i * ROW_H;
			rowPanels.push(panel(150, y, 980, ROW_H - 8, 0xFF000000, 0.45));
			rowTexts.push(label(240, y + 10, 700, "", 32));
		}

		for (s in songs) {
			var icon = new HealthIcon(s.icon);
			icon.scrollFactor.set();
			if (Math.max(icon.width, icon.height) > 56) icon.setUnstretchedGraphicSize(56, 56);
			icon.visible = false;
			icons.push(icon);
			add(icon);
		}

		diffText = label(800, LIST_Y + 12, 320, "", 30, MPColor.ACCENT, RIGHT);
		emptyText = label(0, 300, FlxG.width, "No songs found in this mod.", 30, MPColor.DIM, CENTER);
		emptyText.visible = songs.length == 0;

		label(0, FlxG.height - 42, FlxG.width, "UP / DOWN: song      LEFT / RIGHT: difficulty      ENTER: pick      ESC: back", 18, MPColor.DIM, CENTER);
		label(0, 92, FlxG.width, "Pick the song you want to play. When you are both ready, one of your two picks is rolled.", 20, MPColor.DIM, CENTER);

		updateDifficulties(true);
		refreshUI();
	}

	// ------------------------------------------------------------ difficulties

	function updateDifficulties(first:Bool = false):Void {
		var prevDiff = diffs[curDiff], prevKey = diffKeys[curDiff];
		diffs = [];
		diffKeys = [];
		if (songs.length > 0) {
			var song = songs[selected];
			if (song.difficulties != null) for (d in song.difficulties) {
				diffs.push(d);
				diffKeys.push(null);
			}
			if (song.variants != null && song.metas != null) for (v in song.variants) {
				var meta = song.metas.get(v);
				if (meta != null && meta.difficulties != null) for (d in meta.difficulties) {
					diffs.push(d);
					diffKeys.push(v);
				}
			}
		}
		// keep the same difficulty when moving between songs (or the last used one when opening), if the song has it
		var wantDiff = first ? Options.freeplayLastDifficulty : prevDiff;
		var wantKey = first ? Options.freeplayLastVariation : prevKey;
		curDiff = 0;
		var found = false;
		for (i in 0...diffs.length) if (diffs[i] == wantDiff && diffKeys[i] == wantKey) {
			curDiff = i;
			found = true;
			break;
		}
		if (!found) for (i in 0...diffs.length) if (diffs[i] == wantDiff) {
			curDiff = i;
			break;
		}
	}

	// ------------------------------------------------------------ UI

	function refreshUI():Void {
		if (songs.length > 0) {
			selected = Std.int(FlxMath.bound(selected, 0, songs.length - 1));
			if (selected < top) top = selected;
			if (selected >= top + ROWS) top = selected - ROWS + 1;
			top = Std.int(Math.max(0, Math.min(top, songs.length - ROWS)));
		}

		for (i in 0...ROWS) {
			var idx = top + i;
			var has = idx < songs.length;
			rowPanels[i].visible = rowTexts[i].visible = has;
			if (!has) continue;
			var s = songs[idx];
			var sel = idx == selected;
			rowTexts[i].text = s.displayName != null ? s.displayName : s.name;
			rowTexts[i].color = sel ? MPColor.ACCENT : MPColor.INFO;
			rowPanels[i].alpha = sel ? 0.85 : 0.45;
		}

		for (i => icon in icons) {
			var row = i - top;
			var shown = row >= 0 && row < ROWS;
			icon.visible = shown;
			if (!shown) continue;
			icon.setPosition(170, LIST_Y + row * ROW_H + (ROW_H - 8 - icon.height) / 2);
			icon.alpha = i == selected ? 1 : 0.7;
		}

		if (diffs.length == 0) diffText.text = songs.length == 0 ? "" : "no charts";
		else {
			var t = diffs[curDiff].toUpperCase();
			var key = diffKeys[curDiff];
			if (key != null) t += ' (${key.toUpperCase()})';
			diffText.text = diffs.length > 1 ? '< $t >' : t;
		}
		diffText.y = LIST_Y + Math.max(0, selected - top) * ROW_H + 12;
	}

	override function update(elapsed:Float) {
		super.update(elapsed);

		if (songs.length > 0) {
			var move = (controls.DOWN_P ? 1 : 0) - (controls.UP_P ? 1 : 0) - FlxG.mouse.wheel;
			if (move != 0) {
				selected = FlxMath.wrap(selected + Std.int(move), 0, songs.length - 1);
				CoolUtil.playMenuSFX(SCROLL, 0.5);
				updateDifficulties();
				refreshUI();
			}

			var dmove = (controls.RIGHT_P ? 1 : 0) - (controls.LEFT_P ? 1 : 0);
			if (dmove != 0 && diffs.length > 1) {
				curDiff = FlxMath.wrap(curDiff + dmove, 0, diffs.length - 1);
				CoolUtil.playMenuSFX(SCROLL, 0.5);
				refreshUI();
			}

			if (FlxG.mouse.justPressed) {
				for (i in 0...ROWS) if (rowPanels[i].visible && FlxG.mouse.overlaps(rowPanels[i])) {
					if (top + i == selected) {
						pick();
					} else {
						selected = top + i;
						updateDifficulties();
						refreshUI();
					}
					break;
				}
			}

			if (controls.ACCEPT) pick();
		}

		if (controls.BACK || FlxG.mouse.justPressedRight) {
			CoolUtil.playMenuSFX(CANCEL, 0.7);
			FlxG.switchState(new MultiplayerLobbyState());
		}
	}

	// ------------------------------------------------------------ pick

	function pick():Void {
		if (songs.length == 0 || diffs.length == 0) return;

		var song = songs[selected];
		var key = diffKeys[curDiff];
		var meta = (key == null || song.metas == null) ? song : (song.metas.get(key) != null ? song.metas.get(key) : song);
		var diff = diffs[curDiff];

		var hash = MultiplayerClient.chartHash(meta.name, diff, meta.variant);
		if (hash == null) {
			setStatus('The chart for "${meta.name}" (${diff}) is missing or unreadable.', MPColor.BAD);
			return;
		}

		Options.freeplayLastSong = song.name;
		Options.freeplayLastDifficulty = diff;
		Options.freeplayLastVariation = key;

		client.send({
			t: "song",
			name: meta.name,
			diff: diff,
			variant: meta.variant,
			display: meta.displayName != null ? meta.displayName : meta.name,
			hash: hash
		});
		CoolUtil.playMenuSFX(CONFIRM, 0.7);
		FlxG.switchState(new MultiplayerLobbyState());
	}
}
