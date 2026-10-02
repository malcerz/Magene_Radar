# Magene Radar

Pole danych **Garmin Connect IQ** dla **Garmin Edge 1040**, łączące obsługę radaru **Magene L508** z przednią lampką **Magene AT1200/AT1600**.

Aplikacja pokazuje dane radaru i stan baterii obu urządzeń, a dodatkowo może samodzielnie sterować oświetleniem na podstawie danych Solar albo czasu wschodu i zachodu słońca. Sterowanie lampami działa niezależnie od automatyki Garmin Light Network.

## Najważniejsze funkcje

### Radar Magene L508

Pole korzysta z `Toybox.AntPlus.BikeRadar` i może wyświetlać:

- liczbę pojazdów wykrywanych aktualnie przez radar,
- prędkość względną najbliższego pojazdu,
- dystans do najbliższego pojazdu,
- poziom zagrożenia,
- stronę zagrożenia,
- licznik pojazdów z bieżącej aktywności,
- szacowaną prędkość pojazdu.

Poszczególne informacje można włączać i wyłączać w ustawieniach Connect IQ.

## Bateria AT i L508

Aplikacja odczytuje procent baterii dla:

- **Magene AT1200/AT1600**,
- **Magene L508**.

Podstawowym źródłem dokładnego procentu jest standardowy BLE Battery Service:

```text
Battery Service: 0x180F
Battery Level:   0x2A19
```

Po znalezieniu urządzenia pierwszy odczyt wykonywany jest od razu, a kolejne okresowo, mniej więcej co 60 sekund.

Jeżeli urządzenie udostępnia procent baterii również przez dodatkową stronę ANT+ Bike Lights, aplikacja może wykorzystać tę wartość jako źródło pomocnicze.

## Automatyczne sterowanie oświetleniem

W ustawieniach dostępne są trzy tryby:

- **Wyłączone** — aplikacja nie steruje światłami,
- **Solar** — sterowanie na podstawie `System.getSystemStats().solarIntensity`,
- **Wschód / Zachód słońca** — sterowanie na podstawie pozycji GPS i lokalnie obliczanego czasu wschodu i zachodu.

### Tryb Solar

Zasada jest celowo prosta:

```text
Solar == 0  -> światła ON
Solar > 0   -> światła OFF
```

Jeżeli urządzenie nie udostępnia danych Solar, aplikacja przechodzi na sterowanie według wschodu i zachodu słońca.

## Wschód i zachód słońca

Czas wschodu i zachodu jest liczony lokalnie na Edge na podstawie:

- aktualnej daty i czasu,
- pozycji GPS,
- lokalnej strefy czasowej.

Nie jest wymagane połączenie z telefonem ani internetem.

Po zachodzie światła są włączane, a po wschodzie wyłączane.

## Jasność przedniej lampki AT1200/AT1600

Po włączeniu światła jasność zależy od prędkości roweru:

```text
<= 20 km/h   -> minimalny stały poziom lampki
20-40 km/h   -> jasność ustawiana przez użytkownika
> 40 km/h    -> jasność ustawiana przez użytkownika
```

Dla dwóch wyższych zakresów można wybrać:

```text
20 / 40 / 60 / 80 / 100%
```

Dla prędkości do 20 km/h aplikacja zawsze wybiera najniższy standardowy stały tryb obsługiwany przez Magene AT.

Standardowe tryby stałego światła ANT+ są interpretowane jako:

```text
1 -> 81-100%
2 -> 61-80%
3 -> 41-60%
4 -> 21-40%
5 -> 0-20%
```

## Tylna lampka L508

Dla L508 aplikacja nie próbuje przeliczać jasności na procenty.

Gdy światła mają być wyłączone, ustawiany jest tryb `OFF`. Po ponownym włączeniu aplikacja przywraca ostatni zaobserwowany aktywny tryb L508. Jeżeli nie zna wcześniejszego trybu, używany jest `Solid`.

Obsługiwane tryby L508 obejmują:

```text
0  -> Off
4  -> Solid
5  -> Peloton
6  -> Flashing
7  -> Quickly Flash
62 -> Pulse
63 -> Rotation
```

## Sterowanie ANT+

Lampy są obsługiwane przez standardowe `Toybox.AntPlus.LightNetwork`.

Po wykryciu konkretnego urządzenia aplikacja zapamiętuje odpowiadający mu obiekt `AntPlus.BikeLight` i zmienia tryb przez:

```monkeyc
BikeLight.setMode()
```

Zmiana jest potwierdzana przez aktualizację stanu lampy. Jeżeli urządzenie nie zgłosi żądanego trybu, komenda jest ponawiana z ograniczoną częstotliwością.

Dzięki temu sterowanie dotyczy konkretnej przedniej i tylnej lampki, a nie globalnie wszystkich świateł danego typu.

## Identyfikacja urządzeń

W ustawieniach można podać ręcznie:

- ID przedniej lampki AT,
- ID L508.

Wartość `0` oznacza automatyczne wykrywanie. Po wykryciu aplikacja może zapamiętać numer urządzenia, ale ręcznie wpisany niezerowy identyfikator nie jest automatycznie nadpisywany.

## Układy ekranu

Pole automatycznie dopasowuje liczbę informacji i wielkość fontów do dostępnego miejsca.

Dla Edge 1040 przygotowane są profile odpowiadające przede wszystkim układom:

- 10 pól — do 2 informacji radarowych,
- 9 pól — do 5 informacji,
- 7 pól — do 5 informacji,
- 1 pole — wszystkie włączone informacje.

Bateria AT i L508 jest pokazywana w osobnym wierszu nad danymi radarowymi.

## Ustawienia

Dostępne opcje obejmują:

- pokazywanie baterii AT/LR,
- wybór trybu automatycznego sterowania światłami,
- jasność AT dla 20-40 km/h,
- jasność AT powyżej 40 km/h,
- włączanie i wyłączanie poszczególnych pól radaru,
- ręczne ID AT,
- ręczne ID L508.

## Architektura

Najważniejsze pliki projektu:

```text
source/
├── L508BleDelegate.mc
├── L508BleManager.mc
├── L508RadarManager.mc
├── MageneLightNetworkManager.mc
├── Magene_RadarApp.mc
├── Magene_RadarBackground.mc
├── Magene_RadarView.mc
└── SunTimes.mc
```

### `L508BleManager.mc`

Obsługuje BLE, wyszukiwanie urządzeń, połączenie oraz odczyt Battery Level.

### `L508RadarManager.mc`

Obsługuje `AntPlus.BikeRadar`, targety radaru, licznik pojazdów oraz dane o najbliższym pojeździe.

### `MageneLightNetworkManager.mc`

Obsługuje ANT+ Bike Lights, wykrywanie AT/L508, odczyt pomocniczych danych baterii oraz automatykę oświetlenia.

### `SunTimes.mc`

Oblicza wschód i zachód słońca offline na podstawie pozycji GPS.

### `Magene_RadarView.mc`

Odpowiada za adaptacyjny rendering pola danych.

## Uprawnienia Connect IQ

Projekt wykorzystuje:

```text
Ant
BluetoothLowEnergy
FitContributor
Positioning
Sensor
SensorHistory
```

`Positioning` jest potrzebne do obliczania wschodu i zachodu słońca.

## Budowanie

Projekt jest przeznaczony dla targetu:

```text
edge1040
```

Do kompilacji potrzebne są Garmin Connect IQ SDK oraz klucz deweloperski.

Przykładowe wywołanie:

```powershell
java -Xms1g -Dfile.encoding=UTF-8 `
  -jar "<CONNECT_IQ_SDK>\bin\monkeybrains.jar" `
  -o "bin\Magene_Radar.prg" `
  -f "monkey.jungle" `
  -y "<DEVELOPER_KEY>" `
  -d edge1040 `
  -w -r
```

## Uwagi

Sterowanie światłami zostało zaprojektowane dla zestawu z jedną przednią lampką Magene AT1200/AT1600 i jednym radarem/lampką Magene L508 sparowanymi z Edge przez ANT+.

Dane radaru, BLE i automatyka oświetlenia są od siebie rozdzielone, dzięki czemu utrata jednego kanału komunikacji nie powinna blokować pozostałych funkcji pola.
