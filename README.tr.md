# Ledge

> English: [`README.md`](README.md). Derleme, katkı ve yayın süreci yalnızca
> orada anlatılıyor; bu sayfa kullanıcı içindir.

**Ledge, indirilen dosyaları indikleri anda türlerine göre klasörlere yerleştirir
ve son indirilenleri menü çubuğunda bir tık uzakta tutar; oradan sürükleyip
çalıştığın uygulamaya bırakabilirsin.**

Kurala dayalı düzenleyiciler dosyayı bir yere kaldırır ama az önce indirdiğini
Dock'tan kapma alışkanlığını bozar. Raf uygulamaları dosyayı elinin altında
tutar ama klasörü dağınık bırakır. Ledge ikisini birden yapar.

Gerçek bir `~/Downloads` klasörüne karşı yazıldı: tek bir düz dizinde 1.504 öğe
ve 37 GB.

## Ne yapar

- **Kendiliğinden yerleştirir.** İnmesi biten bir dosya uzantısına göre
  `Images/`, `Videos/`, `Documents/` gibi klasörlere gider. Ledge, dosyanın
  yazılması gerçekten bitene kadar ona dokunmaz.
- **Elinin altında tutar.** Menü çubuğundaki raf, son indirilenleri her birinin
  nereye gittiğiyle birlikte listeler. Bir satırı doğrudan Slack'e, Finder'a
  ya da Premiere'e sürükle; sürüklenen şey gerçek dosyadır, nereye
  yerleştirilmiş olursa olsun.
- **Her şeyi geri alır.** Tek tıkla dosya bulunduğu yere döner.
- **Var olan dağınıklığı toplar.** *Organize Now* neyi taşıyacağını
  taşımadan önce gösterir ve tüm parti tek bir hareket olarak geri alınır.
- **Çalıştığın projeye yerleştirir.** Aşağıda.

## Proje modu

Bir klasörü etkin proje seç; etkin kaldığı sürece indirilenler Downloads'a
değil **o klasöre** yerleştirilir, aynı kurallarla; proje de aynı `Images/`,
`Documents/` alt klasörlerini edinir.

Bu özellik gerçek bir angaryadan çıktı: yirmi beş dosyayı tek tek indirip elle
bir proje klasörüne toplamak. Proje etkinken yalnızca indirirsin.

Etkin proje, rafın üstündeki hedef listesinden ya da Ayarlar'dan seçilir. Geri
dönmek aynı liste; bir projeyi listeden çıkarmak satırın sonundaki eksi. Proje
klasörü ortadan kalkarsa — silindi ya da bağlı olduğu disk çıkarıldı — Ledge
izlenen klasöre yerleştirir ve bunu söyler. Kaldırdığın bir klasörü asla
yeniden yaratmaz.

## İki güvence

Ledge'in gerçekten uyguladığı iki söz bunlar; ikisi de yakalamak için var
oldukları hataya karşı sınanmış testlerle korunuyor:

**Asla üzerine yazmaz.** Hedefte zaten bir `report.pdf` varsa gelen dosya
`report (1).pdf` olur. Bazen değil, her zaman: uygulamadaki her yerleştirme
yolu tek bir taşıyıcıdan geçer ve "boş bir ad seç, sonra taşı" adımını süreç
genelinde sıraya koyar; çünkü ad seçmekle o adı kullanmak tek bir atomik işlem
değildir ve aynı ad için yarışan iki taşıma aksi hâlde ikisi de başarılı olur,
ikincisi ilkini sessizce siler.

**Bir klasörün içine asla inmez.** Bir klasör ya bütün olarak taşınır ya da hiç.
Ledge içeriğini ayıklamak için bir klasöre girmez; bir proje klasörü,
klonlanmış bir depo ya da açılmış bir arşiv olduğu gibi kalır. Bir dizin
yalnızca macOS onu bir paket olarak tanıyorsa (gerçek bir `.app`, gerçek bir
`.sketch` belgesi) uzantısına göre yerleştirilir. Yani adı `footage.mp4` olan
bir klasör video değildir; tek parça hâlinde `Other/`'a gider.

## Geri alma

Her taşıma günlüğe yazılır, bu yüzden geri alma kesindir: dosya bulunduğu
klasöre, özgün adıyla döner.

Geri alma da bir taşımadır; asla üzerine yazmama güvencesi ona da geçer.
Arada aynı adlı bir dosya edinmiş bir klasöre geri koymak, üzerine yazmak
yerine numaralı bir ad üretir.

**Dosya o arada yer değiştirdiyse** Ledge tahmin yürütmez. Dosya günlüğün
kaydettiği yerde değilse — Finder'da taşıdın, adını değiştirdin ya da sildin —
raf satırı *Taşınmış veya silinmiş* der ve geri alma, artık kefil olamadığı bir
yol üzerinde işlem yapmak yerine reddeder. Bir *Organize Now* partisini geri
almak bu kayıtları atlayıp gerisini yerine koyar; tüm partiyi iptal etmez.
Atlanan kayıt günlükte kalır; dosya geri gelirse (Çöp'ten, ya da iCloud veya
Dropbox yeniden eşitlerse) tek tek geri alınabilir.

## Gereksinimler

macOS 14.0 (Sonoma) ve sonrası. Apple Silicon ve Intel için tek bir paket.

Ledge yalnızca menü çubuğunda yaşar; Dock simgesi ve ana penceresi yoktur.

### İzinler

`~/Downloads` macOS tarafından korunur; ilk açılışta erişim sorulur. İzin
verilene kadar Ledge hiçbir şey göremez ve bunu klasörün adını anan bir izin
ekranıyla söyler; menü çubuğunda sağlıklı görünüp hiçbir şey yerleştirmemek
yerine. İzin daha sonra System Settings → Privacy & Security → Files and
Folders'tan verilir.

## Kurulum

1. `Ledge.dmg` dosyasını aç ve **Ledge**'i yanındaki **Applications**
   klasörüne sürükle.
2. Disk imajını çıkar ve Ledge'i `/Applications` içinden başlat. Bağlı imajdan
   değil, oradan: macOS bir uygulamayı DMG üzerinden geçici, salt okunur bir
   konumdan çalıştırır ve oradan kaydedilen "açılışta başlat" ayarı kalıcı
   olmaz.
3. Menü çubuğunda bir tepsi simgesi ara; Dock simgesi ve pencere yoktur.
4. `~/Downloads` klasörüne ilk bakışında macOS izin sorar. Ver; vermezsen ne
   olacağı [İzinler](#i̇zinler) bölümünde.

DMG, Developer ID ile imzalı ve Apple tarafından notarize edilmiştir; hem disk
imajı hem içindeki uygulama kendi onay biletini taşır. Çift tıkla açılır;
sağ tık, uyarı, çevrimdışı istisnası yoktur.

## Yapılandırma

Her şey Ayarlar'da; rafın altındaki dişliden ulaşılır.

**General** — otomatik yerleştirme açık/kapalı, açılışta başlatma, izlenecek
klasörler, projeler ve rafın kaç öğe tutacağı.

**Rules** — kategoriler ve her birine ait uzantılar, öncelik sırasıyla. Sıra
kuraldır: bir uzantıyı ilk sahiplenen kategori kazanır. Her kategori kendi
klasörünü uzantıya göre (`Images/PNG/`) ya da aya göre (`Images/2026-08/`)
bölebilir, ya da hiç bölmez.

Varsayılanlar Images, Videos, Audio, Documents, Archives, Apps, Design, Fonts
ve Code; eşleşmeyen her şey `Other/`'a gider.

Kurallar, projeler ve taşıma günlüğü
`~/Library/Application Support/Ledge/` altında durur.

## Lisans

MIT — bkz. [LICENSE](LICENSE).
