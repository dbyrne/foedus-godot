# Bundled fonts — licenses

All five families are licensed under the **SIL Open Font License v1.1
(OFL-1.1)**, which permits bundling in projects regardless of license,
including commercial, with attribution preserved. Full license text:
https://openfontlicense.org/

Variable fonts are used where the upstream provides one — Godot 4.3
supports the `wght` and `wdth` axes natively. Weight is selected at
use-site via theme variations or direct `FontFile.set_font_variation`.

## Sources

| Family | File | Source | Axes | Upstream |
|---|---|---|---|---|
| Playfair Display | `PlayfairDisplay.ttf` | Google Fonts (variable) | `wght` 400–900 | https://github.com/google/fonts/tree/main/ofl/playfairdisplay |
| Cormorant Garamond | `CormorantGaramond.ttf` | Google Fonts (variable) | `wght` 300–700 | https://github.com/google/fonts/tree/main/ofl/cormorantgaramond |
| Cormorant Garamond Italic | `CormorantGaramond-Italic.ttf` | Google Fonts (variable) | `wght` 300–700 | https://github.com/google/fonts/tree/main/ofl/cormorantgaramond |
| IBM Plex Sans | `IBMPlexSans.ttf` | Google Fonts (variable) | `wdth` 75–125, `wght` 100–700 | https://github.com/google/fonts/tree/main/ofl/ibmplexsans |
| JetBrains Mono | `JetBrainsMono.ttf` | Google Fonts (variable) | `wght` 100–800 | https://github.com/google/fonts/tree/main/ofl/jetbrainsmono |

The OFL.txt for each is identical (the standard SIL OFL 1.1 text). It is
not duplicated here; the canonical text is at
https://openfontlicense.org/open-font-license-official-text/ and the
upstream repos retain their copies.

## Attribution

Per OFL §4, attribution is preserved in this file and in each font's
embedded name table (left untouched).

## Subsetting

Fonts are bundled as full upstream variable TTFs without subsetting.
Subsetting to Latin-only or used-glyphs-only is a possible
optimization for distribution size; deferred until distribution is in
scope.
