@tool
extends RichTextEffect

# [glitch rate=0.3]text[/glitch]: rare flickers under the horror's sweet voice.
# Time is cut into 0.1 s steps; each step is a glitch burst with a chance that
# grows with `rate` (bursts per second, roughly). During a burst, characters
# jump a few pixels, some fade, and a few flash red for one step: something
# wrong showing through. Deterministic per step, so every character in a line
# agrees on when the burst happens.

var bbcode := "glitch"


static func _rand(n: int) -> float:
	return float((n * 1103515245 + 12345) & 0x7fffffff) / float(0x7fffffff)


static func burst(t: float, rate: float) -> bool:
	return _rand(int(t * 10.0) * 7919 + 13) < rate * 0.1


func _process_custom_fx(c: CharFXTransform) -> bool:
	var rate: float = float(c.env.get("rate", 0.3))
	if not burst(c.elapsed_time, rate):
		return true
	var r: float = _rand(int(c.elapsed_time * 10.0) * 131 + c.relative_index * 977)
	if r > 0.32 and r < 0.62:
		return true  # about a third of the letters stay put
	c.offset += Vector2((r - 0.5) * 22.0, (fmod(r * 7.0, 1.0) - 0.5) * 9.0)
	if r > 0.78:
		c.color = Color(1.0, 0.28, 0.42, c.color.a)
	elif r < 0.18:
		c.color.a *= 0.15
	return true
