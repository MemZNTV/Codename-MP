package funkin.multiplayer;

import flixel.input.keyboard.FlxKey;
import openfl.desktop.Clipboard;

/**
 * Keyboard text entry for the multiplayer menus (non-visual, the screen draws `value` however it likes).
 *
 * Characters come from the window's text input events (so shift, keyboard layouts and so on just work),
 * backspace repeats while held and CTRL+V pastes. While enabled the volume/mute hotkeys are switched off,
 * otherwise typing "0", "-" or "+" in an address would change the game volume.
 *
 * Call `update` every frame and `destroy` when the screen closes.
 */
class MPTextInput {
	public var value:String = "";
	public var maxLen:Int = 40;
	/** Called whenever `value` changed by typing/backspace/paste. */
	public var onChange:Void->Void = null;
	public var enabled(default, set):Bool = false;

	var repeatTimer:Float = 0;
	var savedVolume:Array<Array<FlxKey>> = null;

	public function new(?maxLen:Int) {
		if (maxLen != null) this.maxLen = maxLen;
	}

	function set_enabled(v:Bool):Bool {
		if (v == enabled) return v;
		enabled = v;
		if (v) {
			savedVolume = [FlxG.sound.volumeUpKeys, FlxG.sound.volumeDownKeys, FlxG.sound.muteKeys];
			FlxG.sound.volumeUpKeys = [];
			FlxG.sound.volumeDownKeys = [];
			FlxG.sound.muteKeys = [];
			FlxG.stage.window.textInputEnabled = true;
			FlxG.stage.window.onTextInput.add(typed);
		} else {
			FlxG.stage.window.onTextInput.remove(typed);
			FlxG.stage.window.textInputEnabled = false;
			if (savedVolume != null) {
				FlxG.sound.volumeUpKeys = savedVolume[0];
				FlxG.sound.volumeDownKeys = savedVolume[1];
				FlxG.sound.muteKeys = savedVolume[2];
				savedVolume = null;
			}
		}
		return v;
	}

	function typed(text:String):Void {
		if (!enabled) return;
		var clean = text.split("\n").join("").split("\r").join("");
		if (clean.length == 0) return;
		value = (value + clean).substr(0, maxLen);
		changed();
	}

	inline function changed():Void {
		if (onChange != null) onChange();
	}

	function backspace():Void {
		if (value.length == 0) return;
		value = value.substr(0, value.length - 1);
		changed();
	}

	public function update(elapsed:Float):Void {
		if (!enabled) return;
		var k = FlxG.keys;

		if (k.justPressed.BACKSPACE) {
			backspace();
			repeatTimer = 0.45;
		} else if (k.pressed.BACKSPACE) {
			if ((repeatTimer -= elapsed) <= 0) {
				repeatTimer = 0.04;
				backspace();
			}
		}

		if (k.pressed.CONTROL && k.justPressed.V) {
			var data:String = Clipboard.generalClipboard.getData(TEXT_FORMAT);
			if (data != null) typed(data);
		}
	}

	public function destroy():Void {
		enabled = false;
		onChange = null;
	}
}
