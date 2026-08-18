# Magene L508 Radar — Garmin Edge 1040 Data Field

Pole danych Connect IQ dla **Garmin Edge 1040**, które łączy dane z radaru **Magene L508** z dwóch źródeł:

- **BLE** — dokładny procent baterii radaru,
- **ANT+ Bike Radar** — liczba mijających pojazdów i prędkość ostatniego pojazdu.

Projekt jest obecnie rozwijany i testowany na fizycznym **Garmin Edge 1040** oraz **Magene L508**.

## Funkcje

Pole wyświetla trzy informacje:

```text
        Battery: 93%

       12          76
      Cars        km/h
```

- `Battery: 93%` — dokładny poziom baterii L508 odczytany przez Bluetooth Low Energy,
- `Cars` — liczba pojazdów zaliczonych od uruchomienia pola,
- `km/h` — oszacowana bezwzględna prędkość ostatniego zaliczonego pojazdu.

UI jest obecnie przygotowane specjalnie pod **10-polowy layout Edge 1040**.

## Jak to działa

### Bateria przez BLE

L508 udostępnia standardowy Bluetooth Low Energy Battery Service:

```text
Battery Service:  0x180F
Battery Level:    0x2A19
```

Aplikacja:

1. rejestruje profil BLE Battery Service,
2. wyszukuje radar,
3. łączy się z urządzeniem,
4. odczytuje `Battery Level`,
5. aktualizuje odczyt okresowo co około 60 sekund.

Wartość jest odczytywana bezpośrednio jako procent `0–100`.

### Radar przez ANT+

Dane o pojazdach są pobierane przez natywne API Garmin Connect IQ:

```monkeyc
Toybox.AntPlus.BikeRadar
```

oraz:

```monkeyc
getRadarInfo()
```

Dla aktywnych targetów wykorzystywane są m.in.:

```text
RadarTarget.range
RadarTarget.speed
RadarTarget.threat
```

Nie jest otwierany własny surowy kanał ANT. Systemowy radar Edge może nadal działać równolegle.

## Liczenie pojazdów

Nie jest liczona liczba próbek z radaru.

Każdy pojazd jest tymczasowo śledzony na podstawie jego odległości. Pojazd zostaje zaliczony po spełnieniu dwóch warunków:

1. wcześniej znalazł się w odległości nie większej niż:

```text
10 m
```

2. następnie zniknął z listy aktywnych targetów.

Dzięki temu pojedynczy samochód obserwowany przez radar przez kilka sekund nie jest liczony wielokrotnie.

Aktualne stałe śledzenia:

```monkeyc
PASS_DISTANCE_METERS  = 10.0;
MATCH_DISTANCE_METERS = 20.0;
```

## Prędkość pojazdu

Garmin BikeRadar udostępnia prędkość targetu względem rowerzysty.

Prędkość bezwzględna jest obliczana jako:

```text
prędkość pojazdu = prędkość względna radaru + prędkość rowerzysty
```

a następnie konwertowana z `m/s` do `km/h`:

```text
km/h = m/s × 3.6
```

Wartość na ekranie jest zaokrąglana do pełnego `km/h`.

Jeżeli prędkość rowerzysty nie jest dostępna, prędkość pojazdu nie jest aktualizowana na podstawie niepełnych danych.

## Obsługiwane urządzenia

Aktualny `manifest.xml` zawiera wyłącznie:

```text
Garmin Edge 1040
```

Minimalny poziom API:

```text
Connect IQ API 6.0.0
```

Projekt korzysta z uprawnień m.in.:

```text
Ant
BluetoothLowEnergy
FitContributor
Sensor
SensorHistory
```

> Projekt nie był jeszcze przygotowany jako uniwersalne pole dla wszystkich urządzeń Garmin.

## Ważne — identyfikacja BLE

Aktualna wersja jest nadal wersją rozwojową.

W `source/L508BleManager.mc` znajduje się identyfikator testowanego egzemplarza L508:

```monkeyc
name.equals("19813-5")
```

`19813-5` jest nazwą BLE konkretnego egzemplarza radaru i **nie należy zakładać, że będzie taka sama w innym L508**.

Kod dodatkowo rozpoznaje urządzenia, których nazwa zawiera:

```text
L508
```

Przed publikacją jako aplikacja dla innych użytkowników warto dodać:

- skanowanie dostępnych radarów,
- wybór urządzenia,
- zapis wybranego identyfikatora w `Application.Storage`,
- możliwość zmiany lub usunięcia zapamiętanego radaru.

## Jednoczesne połączenie z telefonem

Na testowanym egzemplarzu zaobserwowano, że kiedy Edge utrzymuje połączenie BLE z L508, aplikacja Magene na telefonie może nie widzieć radaru przez Bluetooth.

Nie zostało jeszcze ostatecznie potwierdzone, czy L508 obsługuje tylko jedno aktywne połączenie BLE central w danym momencie.

ANT+ i systemowa obsługa radaru przez Edge działają niezależnie od odczytu baterii BLE.

## Układ pola

Aktualny interfejs jest zoptymalizowany pod **10-polowy ekran danych Edge 1040**.

Najważniejsze fonty:

```monkeyc
batteryFont = Graphics.FONT_SMALL;
valueFont   = Graphics.FONT_NUMBER_MILD;
labelFont   = Graphics.FONT_XTINY;
```

Wartości licznika i prędkości są celowo większe od etykiet.

Pozycje elementów są wyliczane względem rozmiaru przydzielonego pola:

```monkeyc
batteryY = h * 0.05;
valueY   = h * 0.38;
labelY   = h * 0.72;
```

## Struktura projektu

```text
Magene_Radar/
├── manifest.xml
├── monkey.jungle
├── resources/
│   ├── drawables/
│   ├── layouts/
│   └── strings/
└── source/
    ├── L508BleDelegate.mc
    ├── L508BleManager.mc
    ├── L508RadarManager.mc
    ├── Magene_RadarApp.mc
    ├── Magene_RadarBackground.mc
    └── Magene_RadarView.mc
```

Najważniejsze elementy:

### `L508BleManager.mc`

Obsługa:

- rejestracji profilu BLE,
- skanowania,
- połączenia z L508,
- Battery Service,
- Battery Level,
- okresowego odczytu procentu baterii.

### `L508BleDelegate.mc`

Przekazuje callbacki BLE do `L508BleManager`.

### `L508RadarManager.mc`

Obsługa:

- `AntPlus.BikeRadar`,
- pobierania `RadarTarget`,
- śledzenia kilku pojazdów,
- detekcji minięcia,
- liczenia pojazdów,
- obliczania bezwzględnej prędkości.

### `Magene_RadarView.mc`

Pole danych i rendering:

- `Battery: xx%`,
- liczba pojazdów,
- prędkość ostatniego pojazdu.

### `Magene_RadarApp.mc`

Lifecycle aplikacji i inicjalizacja managera BLE.

## Budowanie

Projekt można budować z Visual Studio Code przy użyciu rozszerzenia **Monkey C** i Garmin Connect IQ SDK.

Aktualnie używany target:

```text
edge1040
```

Przykładowe uruchomienie kompilatora z linii poleceń:

```powershell
java -Xms1g -Dfile.encoding=UTF-8 `
  -jar "<CONNECT_IQ_SDK>\bin\monkeybrains.jar" `
  -o "bin\Magene_Radar.prg" `
  -f "monkey.jungle" `
  -y "<DEVELOPER_KEY>" `
  -d edge1040 `
  -w -r
```

Poprawny build kończy się komunikatem:

```text
BUILD SUCCESSFUL
```

## Emulator

Do testów UI można użyć Connect IQ Simulator.

Przykład:

```powershell
simulator.exe
monkeydo.bat bin\Magene_Radar.prg edge1040
```

Emulator pozwala sprawdzić layout pola, ale nie zastępuje testu fizycznego L508 dla BLE i danych radarowych ANT+.

## Logowanie

Kod zawiera komunikaty diagnostyczne przez:

```monkeyc
System.println()
```

Przykłady:

```text
[L508 BLE] connected
[L508 BLE] battery=93%
[L508 BLE] periodic battery read

[L508 ANT] BikeRadar initialized
[L508 ANT] first radar data received
[L508 ANT] target close range=8.2 speed=74
[L508 ANT] vehicle passed count=12 speed=76
```

## Aktualny status

Potwierdzone na sprzęcie:

- połączenie BLE Edge 1040 → Magene L508,
- odczyt standardowego Battery Level,
- dokładny procent baterii, np. `93%`,
- automatyczne pojawienie się radaru BLE po wybudzeniu urządzenia ruchem,
- działanie pola jako Connect IQ Data Field.

W toku dalszych testów:

- dokładność liczenia wielu pojazdów,
- zachowanie śledzenia przy chwilowym zaniku targetu,
- dokładność i rozdzielczość prędkości pojazdów,
- dłuższe testy odświeżania procentu baterii,
- zachowanie BLE przy jednoczesnym użyciu aplikacji Magene na telefonie.

## Ograniczenia

To jest obecnie projekt eksperymentalny / rozwojowy.

W szczególności:

- targetem jest tylko Edge 1040,
- UI jest dostrojone pod layout 10-polowy,
- identyfikacja konkretnego L508 jest częściowo hardcodowana,
- licznik nie jest zapisywany pomiędzy restartami,
- dane pojazdów nie są jeszcze zapisywane do FIT,
- nie ma konfiguracji użytkownika ani wyboru radaru,
- algorytm śledzenia targetów nie korzysta z trwałego ID pojazdu.

## Planowane możliwości

Potencjalne kolejne etapy:

- wybór L508 z poziomu ustawień,
- zapis wybranego radaru,
- poprawiona maszyna stanów reconnect BLE,
- zapis liczby i prędkości pojazdów do FIT,
- statystyki ruchu,
- prędkość maksymalna / średnia,
- obsługa kolejnych modeli Edge i innych layoutów.

## Licencja

Przed publiczną publikacją repozytorium warto dodać wybraną licencję, np. MIT, GPL-3.0 lub inną odpowiednią dla projektu.

Jeżeli nie chcesz jeszcze zezwalać na kopiowanie i redystrybucję, nie dodawaj licencji do czasu podjęcia decyzji.
