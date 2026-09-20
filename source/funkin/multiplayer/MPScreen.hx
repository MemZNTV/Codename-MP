package funkin.multiplayer;

import flixel.text.FlxText;
import flixel.util.FlxColor;
import funkin.backend.FunkinText;

/**
 * Shared look and plumbing for the multiplayer screens (connect, lobby, results):
 * background, title, a status line, and automatic subscription to the server's messages.
 */
class MPScreen extends MusicBeatState {

	var client:MultiplayerClient = MultiplayerClient.instance;

	var bg:FlxSprite;
	var titleText:FunkinText;
	var statusText:FunkinText;

	function screenTitle():String
		return "MULTIPLAYER";

	override function create() {
		super.create();
		CoolUtil.playMenuSong();

		bg = new FlxSprite().loadAnimatedGraphic(Paths.image('menus/menuDesat'));
		bg.color = 0xFF3D4A8C;
		bg.antialiasing = true;
		bg.screenCenter();
		add(bg);

		titleText = label(0, 28, FlxG.width, screenTitle(), 48, MPColor.INFO, CENTER);
		statusText = label(0, FlxG.height - 92, FlxG.width, "", 22, MPColor.INFO, CENTER);

		client.onMessage.add(handleMessage);
	}

	override function destroy() {
		client.onMessage.remove(handleMessage);
		super.destroy();
	}

	/** Every message the server sends, already processed by the client (room snapshot etc.). */
	function handleMessage(m:Dynamic):Void {}

	function setStatus(text:String, color:Int = MPColor.INFO):Void {
		statusText.text = text;
		statusText.color = color;
	}

	function label(x:Float, y:Float, width:Float, text:String, size:Int = 24, color:Int = MPColor.INFO, ?align:FlxTextAlign):FunkinText {
		var t = new FunkinText(x, y, width, text, size);
		t.color = color;
		t.scrollFactor.set();
		if (align != null) t.alignment = align;
		add(t);
		return t;
	}

	function panel(x:Float, y:Float, w:Float, h:Float, color:Int = 0xFF000000, alpha:Float = 0.6):FlxSprite {
		var p = new FlxSprite(x, y).makeGraphic(1, 1, color);
		p.scale.set(w, h);
		p.updateHitbox();
		p.alpha = alpha;
		p.scrollFactor.set();
		add(p);
		return p;
	}

	function goToMainMenu():Void {
		CoolUtil.playMenuSFX(CANCEL, 0.7);
		FlxG.switchState(new funkin.menus.MainMenuState());
	}
}
