# Pick Slip – aplikacja PWA (Flutter Web)

Rozwinięcie arkusza `pick_slip_6037474.xlsx`: lokacje grupowane po **Material ID**,
sumy grup, klasy **S/M/B**, wymiary i waga z bazy produktów, odhaczanie „Zrobione”
i statystyki postępu (lokacje / sztuki / materiały). Działa w przeglądarce,
instaluje się na telefonie jak aplikacja i działa offline.

## Co potrafi

- **Import** pick slipu i danych produktów z **CSV / TSV / TXT, XLSX lub JSON**
  (przycisk ⬆ w pasku). Można wczytać wprost arkusz `pick_slip_*.xlsx` –
  wiersze `SUMA`, `RAZEM` i `POSTĘP` są pomijane.
- **Trzy widoki**: *Wg sumy* (jak karta „Pick Slip”), *Wg wielkości* (B → M → S,
  jak karta „Wg wielkości”) i *Wg lokacji* (trasa po regałach).
- **Odhaczanie** pojedynczych lokacji lub całej grupy; zakończone grupy spadają
  na dół listy, opcja „Ukryj zrobione”, wyszukiwarka lokacji/materiału.
- **Baza produktów** (zamiast Notion): klasa, wymiary, waga, nazwa – z importu
  albo wpisywana ręcznie. Zakładka podpowiada materiały z pick slipu bez danych.
- **Eksport CSV** postępu (układ jak w arkuszu, z wierszami SUMA) i bazy produktów.
- Wszystko zapisuje się lokalnie w przeglądarce (bez serwera).

## Format plików

Separator `;`, `,` lub tabulator – wykrywany automatycznie. Kolumny rozpoznawane
po nagłówkach (kolejność dowolna, wielkość liter bez znaczenia):

| Kolumna | Aliasy | Wymagana |
|---|---|---|
| Location ID | lokacja, lokalizacja | dla pick slipu |
| Quantity | qty, ilość, sztuki | dla pick slipu |
| UOM | jm, jednostka | nie (domyślnie CS) |
| Material ID | material, sku | **tak** |
| Klasa | class | nie |
| Wymiary | dimensions | nie |
| Waga | weight | nie |
| Nazwa | name, opis | nie |
| Zrobione | done | nie (TAK / x / 1 / true) |

Plik **z** kolumną Location ID = nowy pick slip (+ dane produktów, jeśli są).
Plik **bez** niej = tylko aktualizacja bazy produktów. Przykłady: `assets/`.

JSON: lista obiektów z tymi kluczami albo `{"lines": [...], "products": [...]}`.

## Uruchomienie i budowanie

Wymaga Flutter 3.24+ (Dart 3.5+).

```bash
flutter pub get
flutter run -d chrome              # podgląd
flutter build web --release        # wynik w build/web
```

Jeśli Flutter zgłosi brak plików platformy, uruchom raz
`flutter create . --platforms web` – nie nadpisze istniejących plików.

### Publikacja

`build/web` to statyczna strona – wystarczy dowolny hosting z HTTPS
(Netlify, Vercel, Firebase Hosting, GitHub Pages). Dla podkatalogu, np. GitHub Pages:

```bash
flutter build web --release --base-href /nazwa-repo/
```

W repozytorium jest gotowy workflow `.github/workflows/deploy.yml`, który buduje
i publikuje aplikację na GitHub Pages po każdym pushu do `main`
(Settings → Pages → Source: *GitHub Actions*).

### Instalacja na telefonie

Otwórz adres aplikacji → Android/Chrome: *Zainstaluj aplikację*;
iPhone/Safari: *Udostępnij → Do ekranu początkowego*. Po pierwszym otwarciu
działa bez internetu.

## Struktura

```
lib/
  main.dart        UI: kompletacja, produkty, dialogi, import/eksport
  store.dart       stan, sortowanie, statystyki, zapis lokalny
  importer.dart    parser CSV/XLSX/JSON + eksport CSV
  models.dart      PickLine, Product, MaterialGroup
  download*.dart   pobieranie pliku w przeglądarce
web/               index.html, manifest.json, sw.js (offline), ikony
assets/            przykładowy pick slip 6037474 i baza produktów
```
