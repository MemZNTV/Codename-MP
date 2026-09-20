package funkin.multiplayer;

import funkin.backend.FunkinText;
import funkin.menus.FreeplayState;
import funkin.multiplayer.MultiplayerClient.MPStatus;

/**
 * The regular Freeplay list (so it shows exactly the songs of the loaded mod), but selecting a song
 * sends it to the room as the match song instead of starting it.
 */
class MultiplayerFreeplayState extends FreeplayState {
	var client:MultiplayerClient = MultiplayerClient.instance;

	public function new() {
		super(false); // no state scripts: mods' freeplay scripts might start songs on their own
	}

	override function create() {
		super.create();

		var hint = new FunkinText(8, FlxG.height - 30, FlxG.width - 16, "Pick the song you want to play. When you are both ready, one of your two picks is rolled.      ENTER: pick      ESC: back", 18);
		hint.scrollFactor.set();
		add(hint);

		client.onMessage.add(onServerMessage);
	}

	override function destroy() {
		client.onMessage.remove(onServerMessage);
		super.destroy();
	}

	function onServerMessage(m:Dynamic):Void {
		if (m.t == "_closed") FlxG.switchState(new MultiplayerMenuState());
	}

	override function update(elapsed:Float) {
		if (client.status == MPStatus.Disconnected) return;
		super.update(elapsed);
		coopText.visible = false; // versus has no co-op / opponent mode
	}

	override function changeCoopMode(change:Int = 0, force:Bool = false) {}

	override function select() {
		if (curDifficulties.length == 0 || curSong == null) return;

		var diff = curDifficulties[curDifficulty];
		var hash = MultiplayerClient.chartHash(curSong.name, diff, curSong.variant);
		if (hash == null) return; // chart missing/unreadable

		client.send({
			t: "song",
			name: curSong.name,
			diff: diff,
			variant: curSong.variant,
			display: curSong.displayName != null ? curSong.displayName : curSong.name,
			hash: hash
		});
		CoolUtil.playMenuSFX(CONFIRM, 0.7);
		FlxG.switchState(new MultiplayerLobbyState());
	}

	override function goBack() {
		FlxG.switchState(new MultiplayerLobbyState());
	}
}
