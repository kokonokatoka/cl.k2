class_name Hashing
extends RefCounted
## エンジンの版に依存しない安定ハッシュ。ネットワークのコンテンツ照合など、
## 「サーバーとクライアントで同じ値になること」が必要な用途に使う。


## FNV-1a 32bit
static func fnv1a(bytes: PackedByteArray) -> int:
	var h := 0x811C9DC5
	for b in bytes:
		h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF
	return h


static func fnv1a_string(text: String) -> int:
	return fnv1a(text.to_utf8_buffer())
