# Eigene Zutaten-Emojis erzeugen

Der Katalog in `Gnocchi/Resources/ingredient-emojis.txt` legt die Begriffe fest. Für jedes eigene Motiv gibt es eine transparente PNG-Datei in `IngredientEmojis/`. Der Dateiname ist der normalisierte Zutatenbegriff. Änderungen am Katalog können dadurch bei der nächsten Veröffentlichung ergänzt werden.

Vom Repository-Stamm aus arbeiten.

```sh
swiftc ios/scripts/ingredient-emoji-atlas.swift -o /tmp/ingredient-emoji-atlas
/tmp/ingredient-emoji-atlas plan > /tmp/ingredient-emoji-plan.json
```

Jeder Auftrag im Plan besitzt eine feste Reihenfolge und einen Bildgenerator-Prompt für einen 4×4-Bogen. Als Stilreferenz eignet sich ein bestehender Bogen der Gnocchi-Zutaten. Den Plan behalten, bis alle Bögen aus diesem Lauf importiert wurden.

Den Bogen zeilenweise gegen die Zuordnung prüfen und importieren.

```sh
/tmp/ingredient-emoji-atlas import /pfad/zum/bogen.png /tmp/ingredient-emoji-plan.json 1
/tmp/ingredient-emoji-atlas validate
```

Der Import prüft Transparenz und angeschnittene Ränder, zentriert das Motiv und speichert es bei 96×96 Pixeln. Bei einem weitgehend brauchbaren Bogen speichert er die gültigen Zellen und meldet die Fehler. Bereits vorhandene Dateien werden übersprungen. Ein neuer Plan enthält die verbliebenen Begriffe. Mit `plan 3` oder `plan 2` lassen sich für schwierige Motive kleinere Bögen mit mehr Platz anlegen. Ein einzelnes transparentes Bild kannst du mit `single BILD.png BEGRIFF` importieren. `validate` prüft Abmessungen, Transparenz und identische Dateien und meldet die Abdeckung. Der Rückgabewert 2 zeigt, dass noch Begriffe offen sind.

Die Reihenfolge und die Übereinstimmung der Bilder mit den Zutaten müssen bei der Sichtprüfung geprüft werden. Ein passender Bildausschnitt kann auch einen falsch dargestellten Inhalt enthalten.
