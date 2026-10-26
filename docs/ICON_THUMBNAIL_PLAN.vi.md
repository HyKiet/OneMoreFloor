# Kế hoạch icon và thumbnail — One More Floor

> Cập nhật triển khai 25/10/2026: người dùng đã từ chối hướng render 3D và yêu cầu bám thư viện `icons/`, bỏ nền. Bộ hiện tại là [artwork v3](../assets/marketing/v3/README.vi.md): icon 2D viền navy, cel shading, alpha trong suốt; ba thumbnail minh họa cùng phong cách. Các mô tả 3D, prompt và đường dẫn v2 bên dưới là kế hoạch cũ, được thay thế bằng [style contract v3](../assets/marketing/v3/style-contract.vi.md). Người dùng đã upload ảnh và cung cấp 14 Image ID; bộ đã nối vào source UI qua `src/shared/Images.luau`, đồng bộ và kiểm tra render trong Studio. Chưa publish place hoặc đổi metadata icon trên Dashboard. Xem [khảo sát thị trường 12 game/36 thumbnail](market-research/2026-10-25/THUMBNAIL_MARKET_REVIEW.vi.md) trước vòng thử hình tiếp theo.

Ngày lập: 25/10/2026. Cơ sở: [đánh giá dự án](GAME_REVIEW_2026-10-25.vi.md), mã hiện tại, quan sát Studio và metadata MarketplaceService. Đây là brief sản xuất và thử nghiệm; chưa phải bộ artwork hoàn chỉnh và chưa có mẫu thắng được chứng minh bằng dữ liệu.

## Định vị hình ảnh

**“Bạn có dám đánh đổi túi tiền này để xuống thêm một tầng?”** là thông điệp chính. Bổ sung hai thông điệp phụ: né boss cùng bạn bè; bị loại vẫn có thể bỏ phiếu gây khó cho người còn sống.

Hướng art đề xuất: **đồ vật hình khối rõ, vật liệu 3D stylized đơn giản, ánh sáng neon có kiểm soát, chi tiết Art Deco ở nền/phần khung**. Hình quảng bá cần gần hình khối và boss thật của game. Lobby sang trọng là dấu hiệu thương hiệu, còn hành động và lựa chọn của người chơi là điểm nhìn chính.

Đây là giả thuyết thiết kế. Không có bằng chứng hiện tại rằng 3D chắc chắn thắng flat art. Sau khi chọn được nội dung hình hiệu quả, có thể so cùng bố cục với bản flat hiện có để kiểm chứng style.

| Vai trò | Màu gốc từ Theme | Cách dùng |
|---|---|---|
| Nền | Ink `#070812`, Panel `#0D0F1F` | Khối nền yên, giảm hoa văn để silhouette rõ |
| Kiến trúc | Brass `#D4AE68` | Viền thang máy, một vài chi tiết khung |
| Đi sâu/bảo vệ | Cyan `#4EE4FF` | DEEPER, Extra Life, Bless |
| Tiền/thành quả | Gold `#FFCC58` | Túi, cash, VIP, cash-out |
| Nguy hiểm | Red `#FF4858` | Hazard, boss telegraph |
| Lời nguyền | Violet `#AA78FF` | Curse, spectator |
| Hiếm/Daily | Magenta `#FF46AC` | Điểm nhấn; không dùng tràn lên mọi sản phẩm |
| Chữ sáng | Ivory `#F6F0E2` | Chữ UI, chữ thumbnail khi cần |

Ba dấu hiệu lặp lại có chủ đích: **khung cửa thang máy, kim/đồng hồ tầng, túi tiền vàng**. Không nhét cả ba vào từng icon nhỏ.

## Chẩn đoán bộ icon hiện tại

Xem [contact sheet 13 icon hiện có](audit-evidence/existing-product-icons-contact-sheet.jpg).

Ưu điểm: đủ 512×512, đồng bộ nền tối/viền brass, silhouette cơ bản dễ thấy. Nhược điểm: nền tia và khung lặp chiếm nhiều chú ý, cash pack chỉ tăng số chồng coin, Extra Life chỉ khác các dấu nhỏ, một số biểu tượng khá chung chung.

Quan trọng hơn artwork: 9 developer product đang trả về chung icon ID `88963008124478`; 4 pass trả về chung ID `133448903949274`. Cần gán riêng từng ảnh trên Creator Dashboard. Trong shop hiện tại, thẻ sản phẩm dùng `Kit.Icon`, chưa hiển thị các PNG này. Chỉ thay file PNG trong repo sẽ chưa thay được hai bề mặt đó.

## Danh sách 13 icon cần làm

Giá bên dưới lấy từ MarketplaceService trong phiên kiểm tra; không đưa giá lên artwork. Giữ giá bằng chữ UI lấy từ API vì giá có thể thay đổi.

| Key / giá quan sát | Ý tưởng hình chính | Dấu hiệu phụ và nội dung UI | Ưu tiên |
|---|---|---|---|
| `ExtraLife` / 9 R$ | Tim cyan dạng vật thể, mũi tên hồi sinh ôm một phần tim | Nhãn UI `B1–9`; 1 lượt mua không đồng nghĩa thêm nhiều mạng | P1 |
| `ExtraLife2` / 19 R$ | Cùng tim và mũi tên, cùng kích thước và mức hào quang | Nhãn UI `B10–19`; trên ảnh external có biển tầng đơn giản nếu còn đọc rõ | P1 |
| `ExtraLife3` / 29 R$ | Cùng tim và mũi tên | Nhãn UI `B20+`; không thêm ba tim hoặc “×3” vì cả ba tier cùng grant một mạng | P1 |
| `BlessElevator` / 25 R$ | Khiên bubble cyan lớn trước cửa thang máy | Một quầng bảo vệ bao nhóm chấm/nhân vật nhỏ; UI “+1 shield cho người còn sống” | P1 |
| `CurseElevator` / 25 R$ | Mắt rune violet ôm cửa thang máy, hai nét năng lượng hướng vào cửa | “Lời nguyền ở tầng tiếp theo”; tránh dùng boss Eye làm biểu tượng vì đây không phải sản phẩm triệu hồi boss | P1 |
| `GoldenElevator` / 39 R$ | Cabin/cửa thang máy vàng tỏa sáng | Huy hiệu `×2`; đồng hồ nhỏ hoặc UI `15 min · server`, phân biệt với pass cá nhân | P1 |
| `CashSmall` / 49 R$ | Một bó tiền/coin gọn | UI hiển thị số cash thực người này nhận; silhouette thấp | P2 |
| `CashMedium` / 149 R$ | Va-li mở có tiền | Silhouette ngang với nắp bật; khác hẳn bó tiền | P2 |
| `CashLarge` / 399 R$ | Két vàng mở đầy tiền | Silhouette vuông lớn và cửa két; cùng loại tiền với hai gói kia | P2 |
| `VIP` / 149 R$ | Thẻ phòng VIP đen viền vàng, crown nổi trên thẻ | UI nhấn `+1 relic slot`; chữ tăng trưởng phải sửa rõ trước khi đưa vào quảng cáo | P1 |
| `DoubleCash` / 249 R$ | Túi/coin vàng với `×2` lớn | Dùng motif cá nhân, không có nhóm hoặc đồng hồ; UI “mỗi lần cash-out” | P1 |
| `LuckyBellhop` / 199 R$ | Chuông bellhop vàng với cỏ bốn lá xanh gắn rõ trên đỉnh | UI `+25% relic chance · -20% capsule cost`; không diễn đạt thành bảo đảm relic hiếm | P2 |
| `StarterPack` / 99 R$ | Va-li quà mở, tiền + tim + một relic màu rare | UI `$5.000 + 3 Extra Lives + Rare relic`; ba phần phải đọc như bundle | P1 |

Ba Extra Life là ưu tiên **P1** và dùng **một master dùng chung**. Chỉ biến thể biển tầng hoặc nhãn UI, không thay số lượng mạng hay chất lượng hiệu ứng để giả vờ tier đắt mạnh hơn.

Các số giá trong bảng không phải khuyến nghị điều chỉnh giá. `DoubleCash` hiện có ký tự tab cuối tên trong metadata; nên dọn tên khi cập nhật asset.

## Quy cách icon và tích hợp

**File sản xuất:** master RGBA 1024×1024 hoặc vector/scene gốc có thể chỉnh; PNG upload product/pass **512×512**; bản UI có nền trong suốt nếu cần đặt lên thẻ riêng. Giữ nội dung quan trọng trong vòng tròn giữa ảnh để tránh cắt ở các bề mặt external. Roblox quy định ảnh product/pass không vượt 512×512 và lưu ý circular boundaries: [Developer products](https://create.roblox.com/docs/production/monetization/developer-products), [Passes](https://create.roblox.com/docs/production/monetization/passes).

**Bố cục đề xuất:** một chủ thể chính, tối đa một dấu hiệu phụ; chủ thể chiếm khoảng 65–75% chiều rộng; khoảng trống đủ để tròn hóa/crop; bóng tiếp xúc nhẹ; rim light tách nền; nền ít tia hơn bộ cũ. Đây là quy tắc thiết kế của bộ này, không phải yêu cầu của Roblox.

**Chữ:** để tên, giá, số tiền, bậc tầng, thời hạn và mô tả ở UI. Artwork chỉ nên có `×2` nếu cần nhận biết công dụng. Với ảnh external của Extra Life, có thể thêm nhãn tầng sau khi render; không dùng chấm tier nhỏ. Thêm chữ bằng công cụ typography sau khi dựng ảnh để bảo đảm chính xác.

**Kiểm tra trước bàn giao:** xem tại 512, 150, 96, 64 và 48px; kiểm tra crop tròn; grayscale; nền tối và sáng; đặt cả bộ cạnh nhau. Hai người nhìn 1 giây phải phân biệt được Bless/Curse, DoubleCash/Golden và ba cash pack. Extra Life cần cùng nhận diện và đọc tier bằng tên/nhãn phù hợp bề mặt.

**Trong game:** giữ `UI/Icons.luau` cho điều hướng/trạng thái nhỏ. Thêm registry ví dụ `UI/ProductArt.luau` ánh xạ key → image asset ID, hiển thị bằng `ImageLabel` trong thẻ shop, Decision và revive offer. Hero/bundle dùng ảnh khoảng 96–128px; thẻ thường khoảng 64–96px ở độ phân giải UI mục tiêu. Chọn kích thước cuối cùng bằng test trên màn hình thật, không chỉ số virtual px.

**Bề mặt Roblox:** mỗi product/pass được gán ảnh riêng trong Dashboard. Product ID dùng để mua và image asset ID dùng trong `ImageLabel` là hai loại ID khác nhau. Sau upload, kiểm lại metadata, moderation, cache và hình render thật.

**Tên file:** `assets/marketing/icons/v2/<Key>.png`; ảnh UI riêng `<Key>_ui.png`; file nguồn ở thư mục `source/`; manifest có key, product/pass ID, image ID sau upload, revision và trạng thái QA. Giữ bộ cũ làm baseline để so sánh.

## Icon mở rộng ngoài sản phẩm Robux

Không cần làm 46 ảnh từ đầu trong đợt đầu. Sau bộ 13, mở rộng theo nhóm:

| Nhóm | Số lượng | Cách làm |
|---|---:|---|
| Đồ mua trong run | 3 | Bubble Shield: bubble/khiên; Insurance Slip: giấy đóng dấu với túi được bảo vệ; Lucky Charm: charm/cỏ bốn lá |
| Nâng cấp vĩnh viễn | 6 | Insurance: giấy/khiên; Greed: túi với mũi tên tăng; Luck: cỏ; Agility: giày; Starting Shield: khiên cạnh cửa vào; Slots: khay relic có dấu cộng |
| Bộ sưu tập relic | 24 | Render lại chính model trong `ReplicatedStorage.RelicModels` hoặc nguồn Blender; cùng camera, ánh sáng, scale, nền trong suốt |

Tổng là 46 mục nếu tính 13 product/pass + 3 run items + 6 upgrades + 24 relic. Đây là số mục, không phải 46 master độc lập. Không đổi kiểu vẽ của 24 relic thành đồ hoàn toàn khác model người chơi thấy trong game. Polish/Capsule có thể thêm biểu tượng hành động nếu triển khai lại trang Relics, nhưng chưa tính trong 46 mục này.

## Thumbnail: ba giả thuyết đầu tiên

Mục tiêu là tìm hình thu hút **đúng người và khiến họ thực sự chơi**. Chưa có cơ sở gọi một hình là “CTR cao nhất”. Bắt đầu bằng ba thông điệp khác nhau, sau đó tinh chỉnh bố cục/style của thông điệp có tín hiệu tốt.

Xem [sơ đồ bố cục ba concept](audit-evidence/thumbnail-layouts.svg). Các ô trong sơ đồ chỉ đánh dấu vị trí/diện tích; không phải artwork hoặc screenshot game.

### A — “Túi tiền hay thêm một tầng?” — ưu tiên sản xuất đầu

**Câu chuyện:** nhân vật Roblox đứng ở mép cửa thang máy, ôm túi tiền vàng, quay đầu nhìn một đồng đội đang chỉ xuống tầng nguy hiểm. Cửa mở ra arena có dấu cảnh báo đỏ và hình boss Cube thật ở phía xa. Người xem hiểu ngay có một quyết định trước mặt.

**Bố cục 16:9:** nhân vật và túi ở khoảng 1/3 trái, cửa thang máy làm khung ở giữa/phải, nguy hiểm sau cửa. Túi và nét mặt lớn, đường nhìn dẫn vào cửa. Một nhãn ngắn phía trên: `ONE MORE?`; có thể thử bản không chữ. Dùng vàng đối lập cyan/đỏ trên nền navy, giảm các đường trang trí phía sau.

**Giả thuyết:** quyết định mạo hiểm làm game khác với một tuyển tập minigame thông thường. Dùng tiền như thành quả trong game; tránh để hình chỉ còn một đống coin không có hành động.

**Tài sản cần chuẩn bị:** avatar blocky có quyền sử dụng, túi tiền theo ngôn ngữ hình ảnh game, cửa brass/cyan, Cube, một mảng telegraph. Túi cầm tay là minh họa cho bag mechanic; không ám chỉ trong game có cơ chế mang vật lý mới.

**Biến thể vòng sau:** cùng cảnh/camera, đổi duy nhất `ONE MORE?` ↔ không chữ; hoặc đổi nét mặt, không đổi cả boss/camera/style trong cùng phép so sánh.

### B — “Cửa mở, The Cube đang chờ”

**Câu chuyện:** hai hoặc ba người vừa ra khỏi thang máy, một người nhảy qua shockwave của Cube. Cube có đúng hình khối, gương mặt và màu hazard trong game. Có cửa/đồng hồ B5 trong bối cảnh để nhận ra elevator game.

**Bố cục:** boss chiếm khoảng 35–45% khung, avatar tiền cảnh đủ lớn để thấy phản ứng, vòng shockwave tạo đường chéo. Chỉ một boss và một tình huống. Chữ tùy chọn `SURVIVE B5` ở vùng trên.

**Giả thuyết:** hành động dễ hiểu thu hút người thích survival/party, dù có thể kém riêng biệt hơn A. Đây là mẫu thử về hành động, không mặc định là mẫu thắng.

**Mẫu tiếp theo có thể làm:** The Eye với người nấp sau cột thật ở B10. Là concept riêng; không ghép Eye, Cube, lava và xe vào cùng một thumbnail.

### C — “Bị loại rồi vẫn phá bạn”

**Câu chuyện:** góc gần một khán giả trong booth kính đang bỏ phiếu rune violet; dưới arena là hai người sống sót né hazard. Phân cảnh rõ booth và arena, một mũi liên kết thị giác cho thấy bỏ phiếu tác động ván.

**Bố cục:** khán giả/biểu tượng curse bên trái; người sống sót và hiểm họa bên phải; violet đối cyan. Chữ ngắn `THEY VOTED THIS` phía trên nếu cần. Hình vote card là ký hiệu minh họa cho UI đang có, không tạo vật phẩm điều khiển mới.

**Giả thuyết:** vai trò khán giả tạo câu chuyện nhóm bạn và sự tò mò. Rủi ro: cần hiểu nhiều hơn A/B ở ảnh nhỏ. Cần kiểm tra 1 giây thật kỹ. Lời nguyền áp dụng tầng kế tiếp; cảnh là minh họa quan hệ vote → hazard, không quảng bá instant-kill.

## Icon game riêng

Làm thêm **một icon experience 512×512**, tách khỏi icon sản phẩm và thumbnail ngang. Chủ thể: cửa thang máy nửa mở, mặt Cube hoặc mắt boss nhìn từ trong, một avatar tiền cảnh cầm túi, đồng hồ tầng làm điểm nhận diện. Nếu chật, giữ cửa + Cube + một mảng vàng; bỏ chữ nhỏ. Chỉ dùng 2–3 khối lớn.

Roblox khuyên dùng template 512×512 và xem thử khi thu nhỏ, ví dụ 150×150: [Experience icons](https://create.roblox.com/docs/production/publishing/experience-icons). Đây là asset bổ sung có liên quan trực tiếp tới nhận diện game, không phải icon sản phẩm thứ 14.

## Quy cách thumbnail và thư viện nguồn

- Xuất 1920×1080, tỉ lệ 16:9; giữ mỗi file upload dưới 3MB. Master có layer nhân vật/boss/cửa/nền/FX/chữ để làm biến thể.
- Chủ thể phải còn nhận ra ở 320×180 và 160×90. Kiểm tra bản không chữ trước khi thêm headline.
- Không đặt chữ/đồ vật thiết yếu ở đáy vì metadata có thể che. Chừa khoảng thở cạnh ảnh và tránh nhồi HUD thật vào ảnh quảng bá.
- Giữ ít nhất một dấu hiệu elevator ở mỗi concept; nội dung nguy hiểm lấy từ game đã có.
- Làm render/capture sạch từ scene thật hoặc dùng ảnh tham chiếu scene thật để bảo đảm boss và arena khớp. Nếu dùng image generation, tạo từng concept với reference đã kiểm tra; chốt một master ánh sáng/vật liệu rồi mới mở rộng bộ icon. Chữ được ghép sau.
- Tên file: `OMF_TN_A_Risk_v01_1920x1080.jpg`, `OMF_TN_B_Cube_v01_1920x1080.jpg`, `OMF_TN_C_Curse_v01_1920x1080.jpg`.

Các thông số nền tảng và việc tránh phần đáy dựa trên [Thumbnails — Roblox Creator Hub](https://create.roblox.com/docs/production/publishing/thumbnails). Các tỷ lệ diện tích chủ thể và phép thử nhìn 1 giây là đề xuất thiết kế của dự án.

## Prompt khung để sản xuất

Đây là prompt khởi đầu, cần đưa thêm reference thật khi tạo ảnh; chưa gọi công cụ tạo ảnh trong lần đánh giá này.

**Master icon style:**

> A single clearly readable game product object for One More Floor, a Roblox elevator survival game. [OBJECT FROM THE PRODUCT TABLE]. Simple chunky geometry, stylized 3D toy-like materials, restrained neon rim light, midnight navy and warm brass art-deco identity. One main object, one supporting symbol maximum, strong silhouette, generous negative space, calm background. Keep the essential object inside a centered circular safe area. Match the supplied game references. No product prices or small text. Square composition.

Với bản UI cutout, thêm yêu cầu nền trong suốt; với bản upload external, giữ nền navy. `×2` và nhãn tầng thêm sau trong layout.

**Thumbnail A:**

> Roblox-style blocky avatars at the threshold of a midnight art-deco elevator from the supplied One More Floor references. A large foreground avatar on the left protects a glowing gold bag representing earned in-game cash and looks uncertainly toward an open brass and cyan elevator doorway. Beyond the doorway, the actual angry geometric Cube boss and a readable red floor warning create the threat. One clear risk-versus-reward story, expressive face, strong depth, simple silhouettes, cinematic but faithful to the game's primitive neon visual language. Navy background, warm gold reward, cyan doorway, controlled red danger. Leave clean headline space near the top; keep essential subjects away from the bottom overlay area. No lettering, no UI collage. Landscape 16:9.

**Thumbnail B:** thay câu chuyện bằng avatar đang nhảy qua shockwave của Cube tại B5; giữ cửa ở nền và chỉ một boss. **Thumbnail C:** khán giả booth kính chọn rune curse, hai người dưới arena đối diện hazard; giữ mối quan hệ nguyên nhân–kết quả dễ đọc và không vẽ instant-kill.

## Đo hiệu quả và thử nghiệm

**Home thumbnail:** dùng 3 concept A/B/C cùng đợt để kiểm tra thông điệp. Roblox cho bật 2–5 thumbnail cho personalization; mục tiêu của hệ này là qualified play-through rate và có phân phối thích ứng theo nhóm người xem. Vì vậy đây không phải phép A/B chia đều traffic cố định. Nên giữ nhiều hình hoạt động thay vì chọn một “winner toàn cầu” quá sớm. Nguồn: [Thumbnail personalization](https://create.roblox.com/docs/production/publishing/thumbnails).

**Chỉ số cần ghi:** impressions, qualified plays, qPTR, average playtime và winning segment trong dashboard; CTR chỉ tính nếu có số clicks tương ứng và cùng nguồn. `CTR = clicks / impressions`, còn `qPTR = qualified plays / impressions`; không coi hai số là một. Theo dõi thêm bounce sớm, tỷ lệ boarded/floor1 và retention nếu dashboard hỗ trợ phân tích cohort đó.

**Cách chạy:**

1. Ghi baseline theo đúng nguồn Home, khoảng ngày, thiết bị và trạng thái game trước thử nghiệm. Nếu chưa có traffic đủ, ghi “chưa đủ dữ liệu”, không dựng con số CTR mục tiêu giả.
2. Trong đợt hình ảnh, giữ ổn định gameplay, tên, icon game và quảng cáo nếu có thể. Nếu phải sửa lỗi, ghi thời điểm để không quy toàn bộ thay đổi về thumbnail.
3. Theo dõi xuyên cả chu kỳ tuần khi traffic cho phép. Sau vài giờ dashboard có thể có số, nhưng không đủ để kết luận chỉ từ vài chục lượt hiển thị. Độ dài/số mẫu phải theo mức traffic và độ chênh cần phát hiện; một mốc ngày cố định không thay thế đủ mẫu.
4. Đọc kết quả theo segment và mức phân phối; không dùng click rate tổng hợp để tuyên bố nhân quả cho personalization. Không loại mẫu chỉ vì nó có ít impressions.
5. Nếu một hình kéo người vào nhưng playtime/bounce xấu hơn, xem lại kỳ vọng mà hình tạo ra. Ưu tiên chất lượng người chơi, không chỉ click.
6. Đợt tiếp theo giữ 1–2 concept hiệu quả, thêm một biến thể mới thay một yếu tố. Không đổi cả chữ, camera, style và chủ đề rồi gọi đó là test màu.

**Icon sản phẩm trong game:** đo `ProductCardViewed` khi thẻ thực sự vào vùng nhìn, `ProductCardClicked`, `PurchasePromptOpened`, `PurchaseGranted` và product key/surface/revision. Impression cần chống đếm lặp cùng thẻ trong một lần mở; purchase success lấy từ receipt/pass confirmation phía server. Không log mỗi frame. Có thể thử hai bộ ảnh theo cohort nếu triển khai được; so sánh trước/sau đơn thuần chỉ là tín hiệu quan sát.

**Chỉ số phân biệt:** click trên thẻ / lượt thấy thẻ; prompt mở / lượt thấy; mua thành công / lượt thấy; doanh thu trên lượt thấy; với revive còn theo dõi độ sâu và túi đang mất để tránh nhầm thay đổi người chơi với thay đổi artwork. Không có căn cứ bảo đảm bộ icon mới tăng doanh thu bao nhiêu phần trăm.

## Kế hoạch sản xuất và điều kiện hoàn tất

| Chặng | Đầu ra có thể duyệt | Điều kiện qua chặng |
|---|---|---|
| 1. Khóa thông tin | Bảng quyền lợi, giá API, 13 key, reference cảnh/boss/relic | VIP/Extra Life/Daily mô tả khớp luật đã chốt |
| 2. Chốt style | 3 master: Extra Life, Golden Elevator, Starter Pack | Cùng vật liệu/ánh sáng; đọc được ở 64px, crop tròn ổn |
| 3. Mở rộng | 13 file upload và biến thể UI; 1 icon game | Không nhầm hai loại ×2; cash pack khác silhouette; tier không giả số lượng mạng |
| 4. Thumbnail | Ba master A/B/C, bản nhỏ để kiểm tra, file nguồn có layer | Mỗi ảnh kể được một tình huống; boss/arena đúng game; chữ không bị che |
| 5. Tích hợp | Ảnh trong shop/Decision/revive; gán riêng Dashboard | Metadata/image render đúng từng key; shop ngang/dọc đọc rõ |
| 6. Theo dõi | Baseline + log revision + báo cáo personalization/cohort | Kết luận giới hạn theo dữ liệu, có bước thử tiếp theo |

Ước lượng để bố trí nguồn lực: khoảng **4–6 ngày làm việc sản xuất/tích hợp** cho một người có sẵn pipeline, chưa tính moderation, sửa gameplay và thời gian tích lũy traffic. Đây là ước lượng triển khai, không phải lịch đã cam kết. Làm A và ba master icon đầu tiên; chỉ mở rộng khi hệ hình ảnh đọc tốt ở kích thước dùng thật.
