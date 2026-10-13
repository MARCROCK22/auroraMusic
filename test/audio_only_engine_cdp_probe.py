"""Sanitized observation of an existing Android WebView; no browser/profile setup.

Default is read-only. --run-bridge explicitly executes the shipped media script,
including presentation CSS/listeners and the chosen normal playback command.
Requires the environment's existing websocket-client package, not an app dep.
"""

import argparse
import json
from pathlib import Path
import urllib.request
from urllib.parse import urlparse

import websocket


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=9223)
    parser.add_argument("--run-bridge", action="store_true")
    parser.add_argument("--action", choices=["snapshot", "play", "pause", "seek", "volume"], default="snapshot")
    parser.add_argument("--video-id", default="6geljA2OZSY")
    parser.add_argument("--value", type=float)
    options = parser.parse_args()
    if options.action != "snapshot" and not options.run_bridge:
        parser.error("Playback commands require explicit --run-bridge")
    with urllib.request.urlopen(f"http://127.0.0.1:{options.port}/json/list", timeout=5) as response:
        targets = json.load(response)
    pages = [target for target in targets if urlparse(target.get("url", "")).hostname == "music.youtube.com"]
    if len(pages) != 1:
        raise SystemExit("Expected exactly one official Music WebView target")
    endpoint = pages[0]["webSocketDebuggerUrl"]
    if urlparse(endpoint).hostname not in ["127.0.0.1", "localhost"]:
        raise SystemExit("Debugger must remain on loopback")
    expression = """(() => {
      const media = document.querySelector('video, audio');
      const metadata = navigator.mediaSession && navigator.mediaSession.metadata;
      return {
        mediaPresent: !!media,
        readyState: media ? media.readyState : null,
        playing: media ? !media.paused && !media.ended : false,
        position: media && Number.isFinite(media.currentTime) ? media.currentTime : 0,
        duration: media && Number.isFinite(media.duration) ? media.duration : 0,
        adPlaying: !!document.querySelector('.ad-showing, .ad-interrupting'),
        title: metadata ? metadata.title.slice(0, 500) : '',
        artist: metadata ? metadata.artist.slice(0, 500) : ''
      };
    })()"""
    if options.run_bridge:
        source = (Path(__file__).resolve().parents[1] / "lib/audio_web/web_music_bridge.dart").read_text(encoding="utf-8")
        script = source.split("const webMusicMediaScript = r'''", 1)[1].split("''';", 1)[0]
        arguments = {"action": options.action, "expectedId": options.video_id, "generation": 1, "value": options.value}
        declarations = ";".join(f"const {key}={json.dumps(value)}" for key, value in arguments.items())
        expression = f"(async () => {{ {declarations}; {script} }})()"
    connection = websocket.create_connection(endpoint, timeout=12, suppress_origin=True)
    try:
        connection.send(json.dumps({"id": 1, "method": "Runtime.evaluate", "params": {
            "expression": expression, "awaitPromise": True, "returnByValue": True,
        }}))
        while True:
            message = json.loads(connection.recv())
            if message.get("id") == 1:
                break
        result = message.get("result", {})
        if "exceptionDetails" in result or "error" in message:
            raise SystemExit("Evaluation failed (details suppressed to protect site data)")
        value = result.get("result", {}).get("value", {})
        allowed = ["status", "mediaPresent", "readyState", "playing", "buffering", "ended", "adPlaying", "position", "duration", "volume", "mediaError", "title", "artist"]
        sanitized = {key: value[key] for key in allowed if key in value}
        # Provider metadata is untrusted text; do not log embedded URLs.
        for key in ["title", "artist"]:
            if "http" in str(sanitized.get(key, "")).lower():
                sanitized[key] = "[metadata URL suppressed]"
        print(json.dumps(sanitized, ensure_ascii=True))
    finally:
        connection.close()


if __name__ == "__main__":
    main()
