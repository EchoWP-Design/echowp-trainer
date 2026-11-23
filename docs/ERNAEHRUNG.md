# Kalorien- und Makrorechner

Die App kennt zwei Modi, umschaltbar unter **Daten → Profil & Ernährung**.

## Jan-Formel (aus `Rechner_Kalorien.xlsx`)

| Wert | Formel | Bewertung |
|---|---|---|
| Kalorien | Gewicht × 26 | Faustregel. Ignoriert Alter, Größe, Geschlecht und Aktivität; bei viel Training meist zu niedrig (übliche Spanne 30–38 kcal/kg). |
| Protein | Gewicht × 2 g | Passt (ISSN: 1,4–2,0 g/kg, im Defizit bis 2,2). |
| Fett | Kalorien / 30 g | Entspricht 30 % der Energie, passt zur DGE. |
| Ballaststoffe | Kalorien × 0,014 g | 14 g je 1000 kcal, gängige Referenz. DGE nennt zusätzlich mindestens 30 g. |
| Kohlenhydrate | (Kalorien − Protein·4 − Fett·9) / 4 | Rechenweg korrekt, Ergebnis aber durch die niedrigen Kalorien oft unter 3 g/kg. |
| Wasser | Gewicht / 30 l | Als Grundbedarf ok (≈ 33 ml/kg), ohne Trainingszuschlag. |

## Wissenschaftlich (Standard)

- **Grundumsatz** nach Mifflin-St Jeor: Männer `10·kg + 6,25·cm − 5·Alter + 5`, Frauen `… − 161`.
- **Gesamtumsatz** = Grundumsatz × PAL. Der PAL folgt aus den Trainingsstunden der
  letzten vier Wochen (Garmin): unter 1 h/Woche 1,4 · 1–3 h 1,55 · 3–5 h 1,7 · 5–8 h 1,85 · ab 8 h 2,0.
  Märsche zählen zu 80 %, Mobility zu 30 %.
- **Ziel**: Abnehmen −15 %, Halten ±0, Aufbauen +10 %.
- **Protein** 2,0 g/kg, im Defizit 2,2 g/kg.
- **Fett** 30 % der Energie, mindestens 0,8 g/kg.
- **Ballaststoffe** 14 g je 1000 kcal, mindestens 30 g.
- **Kohlenhydrate** = Rest. Hinweis, wenn unter 3 g/kg bei mindestens 3 h Ausdauer pro Woche.
- **Wasser** 35 ml/kg plus 0,75 l je Trainingsstunde des Tages.

Fehlen Größe, Geburtsjahr oder Geschlecht, rechnet die App mit der Jan-Formel und sagt das.

Quellen: Mifflin et al. 1990 (Am J Clin Nutr); Frankenfield et al. 2005 (Vergleich der
Grundumsatzformeln); ISSN Position Stand Protein 2017; ACSM/AND/DC Nutrition and
Athletic Performance 2016; DGE-Referenzwerte (Fett, Ballaststoffe, PAL); EFSA
Referenzwerte Wasser 2010.
