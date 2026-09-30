# PRÍDEL Flutter beta 0.5.1

Čisté Flutter jadro rodinného plánovača jedla. Nepoužíva WebView. Táto verzia rozširuje stabilné jadro o prvky, ktoré používateľ očakáva od bežnej mobilnej aplikácie, bez pridania cloudu alebo účtu.

## Prvé spustenie a Domov

- úvodné nastavenie domácnosti,
- voľba, či sa majú využívať zásoby,
- voľba bežného horizontu plánu 7 / 14 / 28 dní,
- zapnutie/vypnutie upozornení v aplikácii,
- nová obrazovka Domov s dnešným jedlom, rýchlymi akciami, zásobami, nákupom, históriou a štatistikami,
- prioritné upozornenie sa zobrazí ako horný banner; po `Potvrdiť` sa uloží ako vybavené a zmizne,
- ďalšie upozornenia zostanú prehľadne na Domove.

## Zásoby

Pôvodný jeden Sklad je rozdelený na:

- **Chladnička**,
- **Špajza**,
- **Mraznička**.

Každá položka má množstvo, jednotku, umiestnenie a voliteľný dátum spotreby. Existujúce položky sa pri migrácii rozumne zaradia podľa kategórie. Nové nákupy sa zaraďujú automaticky a umiestnenie sa dá zmeniť.

Pribudlo rýchle zadanie typu `Mlieko 2 l`, vyhľadávanie a `Navrhni jedlo z tejto suroviny`.

Globálny prepínač `Využívať zásoby` zostáva. Ak je vypnutý, zásoby sa neodpočítavajú z nákupu ani neovplyvňujú plánovanie, ale údaje sa nemažú.

## Recepty a varenie

- 174 vstavaných receptov + vlastné recepty,
- vyhľadávanie podľa názvu a suroviny,
- filtre Obľúbené, Moje, Zo zásob, Do 30 min a Nedávno,
- blokovanie receptu z automatických návrhov,
- bezpečný snapshot receptu v histórii,
- samostatný **Režim varenia** s veľkým textom a krokmi po jednom.

## Jedálniček

- reálny kalendár bez štvortýždňového limitu,
- tlačidlo doplní prázdne jedlá na 7 / 14 / 28 dní podľa nastavenia,
- výmena receptu zohľadňuje domácnosť, alergény, zásoby, expirácie, cenu, čas, energiu, pestrosť a opakovanie,
- zvyšky majú prednosť, ak sú kompatibilné a je ich dosť,
- pravidlá týždňa sledujú ryby, bezmäsité a strukovinové jedlá, ovocie, zeleninu, sladké hlavné jedlá a opakovanie zdroja bielkovín,
- ide o orientačné plánovanie, nie individuálnu medicínsku diétu.

## Nákup

- zlúčenie rovnakých surovín,
- odpočet reálnych zásob pomocou FEFO,
- celé balenia a orientačná cena,
- vlastné ceny balení,
- ručné položky,
- fajka Kúpené,
- kúpené potraviny sa dajú pridať do zásob,
- zoznam sa dá skopírovať a poslať partnerovi alebo komukoľvek inému bez účtu.

Reálny živý spoločný zoznam medzi dvoma telefónmi zámerne ešte nie je zapnutý. Vyžaduje cloud/účet a patrí do samostatnej synchronizačnej vrstvy, aby offline aplikácia zostala stabilná a súkromná.

## Zvyšky a Undo

- Hotovo je transakčné a eviduje reálne odpočty zásob,
- pri chýbajúcich zásobách upozorní,
- zvyšky majú počet porcií a dátum spotreby,
- zvyšok sa dá zjesť, naplánovať alebo vyhodiť,
- po vyhodení je dostupné `Vrátiť`.

## História, úložisko, záloha a diagnostika

- história hotových jedál s nemennými snapshotmi,
- základné mesačné štatistiky na Domove,
- obrazovka Úložisko/Diagnostika ukazuje veľkosť databázy a počty dát,
- lokálny technický log posledných chýb,
- diagnostiku možno skopírovať pre podporu,
- kompletnú zálohu je možné exportovať do schránky a znovu importovať,
- import kontroluje identitu a verziu formátu zálohy.

## Výkon a pamäť

- SQLite + WAL + indexy + migrácie,
- obrazovky reagujú iba na relevantné zmeny,
- asynchrónne načítania používajú tokeny proti prepísaniu novšieho stavu starou odpoveďou,
- zoznamy a databáza sa nenačítavajú ako jeden obrovský dokument,
- žiadny WebView a žiadny `renderAll()`.

## Tablet a prístupnosť

- mobil používa spodnú navigáciu,
- tablet používa NavigationRail a širšie rozloženie,
- aplikácia rešpektuje systémovú veľkosť textu,
- tlačidlá a akčné prvky používajú Material 3 rozmery a tooltips.

## Súkromie

- bez povinného účtu,
- bez polohy, kontaktov a mikrofónu,
- bez vzdialeného servera,
- Android beta zakazuje cleartext HTTP a systémový backup aplikácie,
- používateľské dáta sú lokálne v SQLite.

## Zámerne až po stabilnom APK

Nasledujúce veci už zasahujú do oprávnení, cloudu alebo produkčnej distribúcie a nepcháme ich do prvého stabilného Flutter buildu naraz:

- systémové push/local notifikácie mimo otvorenej aplikácie,
- živá synchronizácia spoločného nákupného zoznamu medzi zariadeniami,
- skenovanie čiarových kódov a účteniek,
- fotografie jedál a vlastné fotografie receptov,
- cloudová záloha/účet,
- predplatné a Play Billing,
- Play Integrity, produkčný signing a AAB.

Tieto vrstvy sú oddelené zámerne, aby ich bolo možné pridať bez prerábania dátového jadra.

## Automatická kontrola pred APK

Workflow vykoná v tomto poradí:

1. `python tool/validate_seed.py`,
2. `python tool/validate_project.py`,
3. `flutter pub get`,
4. `flutter analyze`,
5. `flutter test`,
6. až potom `flutter build apk --debug`.

Ak kontrola, analyzér alebo testy zlyhajú, APK sa nevydá ako úspešný artifact.


## 0.6.1
- smoke test separated from real SQLite FFI integration tests to prevent CI timeout
- database initialization and backup round-trip remain covered in database_test.dart


## 0.6.2
- initializes sqflite_common_ffi before constructing the AppDatabase test double in the widget smoke test
