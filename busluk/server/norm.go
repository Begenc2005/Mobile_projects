package main

import (
	"strings"
	"unicode"
)

// norm приводит текст к единому виду для поиска:
// нижний регистр, кириллица (рус. и туркм.) -> латиница, туркменские буквы -> ASCII.
// Благодаря этому «тойота», «Toyota», «maşyn», «mashyn» находятся одинаково.
var tr = map[rune]string{
	'а': "a", 'б': "b", 'в': "v", 'г': "g", 'д': "d", 'е': "e", 'ё': "yo", 'ж': "z",
	'з': "z", 'и': "i", 'й': "y", 'к': "k", 'л': "l", 'м': "m", 'н': "n", 'о': "o",
	'п': "p", 'р': "r", 'с': "s", 'т': "t", 'у': "u", 'ф': "f", 'х': "h", 'ц': "ts",
	'ч': "ch", 'ш': "sh", 'щ': "sh", 'ъ': "", 'ы': "y", 'ь': "", 'э': "e", 'ю': "yu",
	'я': "ya", 'ә': "a", 'ө': "o", 'ү': "u", 'ң': "n", 'җ': "j",
	'ä': "a", 'ç': "ch", 'ş': "sh", 'ň': "n", 'ö': "o", 'ü': "u", 'ý': "y", 'ž': "z",
	'w': "v", 'x': "ks", 'q': "k",
}

func norm(s string) string {
	var b strings.Builder
	b.Grow(len(s))
	space := true
	for _, r := range strings.ToLower(s) {
		if t, ok := tr[r]; ok {
			b.WriteString(t)
			space = false
			continue
		}
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			b.WriteRune(r)
			space = false
		} else if !space {
			b.WriteByte(' ')
			space = true
		}
	}
	return strings.TrimSpace(b.String())
}

// normPhone: «+993 65 12-34-56», «865123456», «65123456» -> «99365123456».
func normPhone(s string) string {
	d := make([]byte, 0, 12)
	for i := 0; i < len(s); i++ {
		if s[i] >= '0' && s[i] <= '9' {
			d = append(d, s[i])
		}
	}
	p := string(d)
	switch {
	case len(p) == 11 && strings.HasPrefix(p, "993"):
	case len(p) == 9 && p[0] == '8':
		p = "993" + p[1:]
	case len(p) == 8:
		p = "993" + p
	default:
		return ""
	}
	if p[3] != '6' && p[3] != '7' {
		return ""
	}
	return p
}
