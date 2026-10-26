# Thumbnail Roblox: khảo sát và đánh giá One More Floor

Ngày khảo sát: **25/10/2026**, theo ngày người dùng cung cấp. Phạm vi: 12 game, 36 thumbnail công khai từ Roblox. Kết luận: **chưa thể bảo đảm thumbnail One More Floor có CTR cao nhất**. Chất lượng mỹ thuật và khảo sát đối thủ giúp đặt giả thuyết; kết quả phải được đo trên chính audience, nguồn hiển thị và phiên bản game của bạn.

## Cách khảo sát

Chọn mẫu có chủ đích, ưu tiên cùng cơ chế hoặc cùng nhu cầu người chơi: elevator, minigame, survival, run theo nhóm và né nguy hiểm. Bổ sung một vài game lớn để xem cách tạo nhận diện ở phạm vi rộng. Đây không phải mẫu ngẫu nhiên hoặc toàn bộ thị trường Roblox.

Đọc Roblox Charts để định hướng thị trường; sau đó lấy metadata và hình trực tiếp qua public Roblox API:

1. `apis.roblox.com/universes/v1/places/{placeId}/universe` để xác nhận universe.
2. `games.roblox.com/v1/games?universeIds=...` để kiểm lại tên game và metadata.
3. `thumbnails.roblox.com/v1/games/multiget/thumbnails` với `countPerUniverse=3`, `size=768x432`, `format=Png` để lấy ảnh.
4. Tải và xem đủ 36 ảnh, cùng kích thước, không dựa vào ảnh YouTube, Google Images hoặc fan art để suy ra thumbnail của game.

Ảnh là các thumbnail gallery được API trả về lúc khảo sát. Không có bằng chứng chúng là thumbnail Home mà mọi người dùng đều thấy; Home có thể cá nhân hóa. Thứ tự #1/#2/#3 ở đây là thứ tự API, **không phải xếp hạng CTR**. Một số ảnh có thể là artwork cũ vẫn nằm trong gallery. Không suy ra ngày tạo ảnh từ ngày tải ảnh.

Nguồn thô nằm trong `sample-games.json`, `game-details.json`, `thumbnail-api-response.json`, cùng thư mục `images/`. Các URL CDN và target asset ID được giữ để kiểm lại. Số người chơi trong metadata chỉ là snapshot tham khảo, không dùng để đánh giá CTR hoặc chứng minh ảnh hiệu quả.

Xem [bảng 12 game](market-contact-sheet.jpg), và toàn bộ ảnh ở [trang 1](gallery-page-1.jpg), [trang 2](gallery-page-2.jpg), [trang 3](gallery-page-3.jpg), [trang 4](gallery-page-4.jpg).

## Quan sát trực tiếp từng nhóm

Các nhận xét bên dưới là phân tích thị giác của mẫu đã tải, không phải thông tin CTR do nhà phát triển công bố.

| Game / nguồn chính thức | Quan sát trong ba ảnh | Bài học phù hợp với One More Floor |
|---|---|---|
| [Regretevator](https://www.roblox.com/games/4972273297) | Có minh họa 2D nhân vật lớn và cả cảnh 3D trong cabin; cùng wordmark dễ nhận ra | Nhân vật và dấu hiệu elevator có thể giữ nhận diện qua nhiều style. Không có căn cứ nói chỉ 3D hoặc chỉ 2D mới hiệu quả |
| [The Normal Elevator](https://www.roblox.com/games/230362888) | Cửa mở ra portal hoặc một cảnh khác; avatar nhỏ hơn cửa; tên game trên cùng | Cửa là khung kể chuyện tự nhiên: người xem tò mò điều gì ở tầng tiếp theo |
| [Epic Minigames](https://www.roblox.com/games/277751860) | Cảnh minigame hoặc nhân vật khối, logo xanh lớn lặp lại | Một hoạt động dễ hiểu và một dấu hiệu thương hiệu cố định giúp liên kết các minigame khác nhau |
| [Super Bomb Survival](https://www.roblox.com/games/164051105) | Tranh 2D nhiều biểu cảm, avatar bị đe dọa bởi bomb; thêm ảnh bản đồ 3D | Illustration là lựa chọn hợp lệ trong nhóm này. Nguy hiểm và phản ứng phải đọc được trước chi tiết trang trí |
| [Natural Disaster Survival](https://www.roblox.com/games/189707) | Đảo/map với thiên thạch hoặc núi lửa, thêm một tranh 2D | Cảnh “mối nguy đang xảy ra” tự kể được luật chơi, không cần chỉ vẽ avatar đứng tạo dáng |
| [The Floor Is LAVA!](https://www.roblox.com/games/815405518) | Biển lava bao tòa nhà; avatar gặp nguy hiểm; có biến thể crop gần và mũi tên | Silhouette mối nguy và khoảng an toàn rất rõ. Học tính rõ ràng, không mặc định sao chép mũi tên sẽ tăng click |
| [DOORS](https://www.roblox.com/games/6516141723) | Không gian tối có một thực thể, cửa và wordmark; một mẫu có viền sự kiện đỏ | Logo/cửa/thực thể làm điểm neo. Không sử dụng branding sự kiện mà game mình không tham gia |
| [Pressure](https://www.roblox.com/games/12411473842) | Đỏ–đen, trắng–đen và xanh–đen; silhouette thực thể/không gian mạnh | Khác biệt màu và silhouette có thể hữu ích hơn việc thêm nhiều chi tiết. Không đồng nhất “đẹp, nhiều vật liệu” với hiệu quả thumbnail |
| [Dandy's World](https://www.roblox.com/games/16116270224) | Mascot rất lớn, rõ mặt; bối cảnh ánh sáng có chủ ý; wordmark lặp lại | One More Floor có thể biến The Cube thành điểm nhận diện riêng, nhưng cần lặp lại nhất quán qua các lần phát hành |
| [Evade](https://www.roblox.com/games/9872472334) | Avatar ở tiền cảnh, tương tác trong bối cảnh; màu tím/xanh hoặc xanh lá mạnh | Hình cần gợi hoạt động và quan hệ giữa người chơi, không chỉ đặt họ cạnh nhau |
| [99 Nights in the Forest](https://www.roblox.com/games/79546208627805) | Deer lớn đối diện người chơi/camp; tương phản nguy hiểm và nơi trú ẩn | Một mối đe dọa có silhouette riêng và một tình huống dễ đọc. Không dùng quái vật của đối thủ cho game mình |
| [Tower of Hell](https://www.roblox.com/games/1962086868) | Gallery giới thiệu tower, gear và đích đến, có chữ mô tả feature | Gallery còn làm nhiệm vụ giải thích nội dung sau khi người dùng vào trang. Không coi mọi ảnh gallery là creative Home đã được tối ưu |

## Mẫu hình đáng áp dụng

**1. Đọc tình huống nhanh hơn đọc kỹ xảo.** Những ví dụ rõ gồm lava bao tòa nhà, meteor lao vào đảo, deer phía sau người chơi và cửa elevator mở ra portal. Với One More Floor, khoảnh khắc nhảy qua shockwave dễ hiểu hơn một collage gồm boss, coin, relic và nhiều lời nguyền.

**2. Cần có điểm nhận diện riêng.** Cube cyan với gương mặt vuông, đồng hồ bán nguyệt, cửa hai hình thoi và quyết định DEEPER/LEAVE là tài sản của game. Chỉ dùng avatar sợ hãi với coin sẽ dễ trở thành một thumbnail survival chung chung.

**3. Thị trường không có một style duy nhất.** Trong mẫu này có illustration phẳng, cảnh 3D, ảnh gameplay và đồ họa gần đơn sắc. Chưa đủ bằng chứng để nói “vẽ y như top game” hoặc “3D chắc chắn thắng 2D”. Giữ bộ 2D viền navy mà bạn đã chọn là một quyết định nhận diện hợp lý; hiệu quả click vẫn cần kiểm chứng.

**4. Thông tin nên có thứ bậc.** Ngay cả mẫu nhiều chi tiết thường có mascot, face, logo hoặc threat để neo mắt. Nếu mọi mảng đều vàng sáng hoặc có độ nổi bằng nhau, mắt khó biết xem gì trước. Chi tiết thu nhỏ không đọc được nên giảm hoặc đưa sang ảnh gallery giải thích sâu.

**5. Event creative là một biến riêng.** Trong mẫu có artwork/khung Halloween hoặc “The Hollow”. Đó là bối cảnh nội dung thực tế của những game đó. Không thể tách tác dụng của hình khỏi sự kiện, thương hiệu, lịch cập nhật và audience đang quay lại.

## Đánh giá thẳng ba thumbnail v3 hiện có

Đối chiếu [bản 320px và 160px của One More Floor](../../../assets/marketing/v3/previews/thumbnails-overview.jpg). Đây là đánh giá đọc hình của người thiết kế, chưa phải kết quả test người chơi.

| Mẫu | Điểm mạnh | Điểm cần cải thiện | Vai trò trong thử nghiệm |
|---|---|---|---|
| A — Risk | Có nhân vật ôm tiền, cửa đặc trưng và Cube; gợi được nỗi sợ mất thành quả | Áo, túi và khung cửa đều vàng/cam nên cạnh tranh chú ý. Chưa diễn đạt rõ lựa chọn “ra lấy tiền hay xuống tiếp”; có thể bị đọc là trốn khỏi quái vật | Giữ làm mẫu định vị nét riêng; vòng sửa nên làm rõ quyết định và tăng tách màu nhân vật/cửa |
| B — Cube | Ở 160px vẫn thấy mặt boss, avatar đang nhảy và vòng đỏ. Trong ba mẫu, đây là cảnh dễ đọc nhất theo đánh giá thị giác của mình | Chưa thể hiện tiền hoặc lựa chọn rủi ro; người mới có thể hiểu là minigame né boss thuần túy. Cần tránh để mặt boss phủ hết hành động | Ưu tiên cùng A trong đợt Home đầu vì luật “né nguy hiểm” rõ; chưa gọi là mẫu CTR cao nhất |
| C — Curse | Có twist xã hội, booth, vote và survivor; dùng được làm ảnh gallery giải thích cơ chế | Nhiều quan hệ cần hiểu: khán giả, vote card, eye trên arena và người bên dưới. Ở kích thước rất nhỏ khó hiểu hơn A/B | Giữ để thử segment nhóm bạn hoặc làm ảnh thứ ba; nếu impressions thấp không kết luận ngay là hình tệ |

### Vòng chỉnh tiếp theo có căn cứ

- **A1 — làm rõ quyết định:** vẫn giữ cùng illustration, giảm vàng trên áo hoặc nền gần avatar; túi tiền là điểm vàng chính ở tiền cảnh, cửa ở phía sau. Có thể thử một bản với hai nhãn UI thật `LEAVE` / `DEEPER`, hoặc chỉ headline `ONE MORE?`. Chọn một thay đổi để kiểm tra mỗi lần; không đổi cả text/camera/style/threat rồi gọi đó là test chữ.
- **B1 — tăng nét riêng:** giữ boss và shockwave, cửa/dial nhìn rõ; thử thêm túi tiền như yếu tố gameplay nhỏ nếu nó không làm avatar khó đọc. Không tự nhận tăng CTR trước khi có số.
- **C1 — giảm tầng thông tin:** crop gần một khán giả và một người sống sót; chỉ một rune vote rõ, giảm eye lặp và chi tiết sàn. Giữ đúng curse tác động tầng tiếp theo, không diễn đạt thành nút giết người tức thì.

Trong tác vụ khảo sát này chưa tạo thêm artwork để không thay toàn bộ creative trước khi có baseline. Các biến thể trên là đề xuất cho vòng thử tiếp theo, không phải file đã được xuất.

## Cách xác định hiệu quả thực tế

Roblox cho bật nhiều thumbnail và phân phối theo người xem; tài liệu nêu mục tiêu là qualified play-through rate, không chỉ click. Có thể bật 2–5 ảnh, rồi xem impressions, qualified plays, qPTR, average playtime và winning segment. Nguồn: [Roblox Thumbnails](https://create.roblox.com/docs/production/publishing/thumbnails).

Đề xuất ban đầu: **bật A và B cùng lúc**, có thể thêm C nếu muốn kiểm tra audience nhóm bạn. Giữ nhiều mẫu hiệu quả hoạt động vì personalization có thể tìm mẫu phù hợp cho từng nhóm. Không coi traffic của hệ này là A/B chia đều cố định.

| Chỉ số | Cách hiểu |
|---|---|
| CTR | Clicks / impressions của cùng một bề mặt. Chỉ tính nếu có số clicks tương ứng; không đổi tên qPTR thành CTR |
| qPTR | Qualified plays / impressions từ Home; thể hiện số lần chơi có ý nghĩa trên lượt hiển thị |
| Average playtime | Giúp kiểm tra người click có thực sự tiếp tục chơi hay không |
| Early bounce / onboarding | Đối chiếu kỳ vọng hình quảng bá với trải nghiệm vào game; đọc theo cohort/source nếu dữ liệu hỗ trợ |
| Winning segment | Một ảnh có thể phù hợp một nhóm mà không thắng mọi nhóm |

Ghi baseline theo khoảng ngày, nguồn Home, thiết bị và phiên bản game. Trong đợt thử, giữ ổn định tên/icon game, bản gameplay và chiến dịch quảng cáo khi có thể; nếu thay, ghi thời điểm. Xem xuyên chu kỳ tuần khi traffic cho phép nhưng không lấy mốc 7 ngày thay thế đủ mẫu. Không kết luận từ vài chục impressions hoặc vài clicks.

Không có một ngưỡng “CTR tốt” chung có thể bảo đảm thành công cho mọi game, device, audience hoặc nguồn traffic. Cũng không thể lấy số người đang chơi, lượt thích hay doanh thu của đối thủ để đảo ngược ra CTR của từng hình. Các game nổi tiếng có thương hiệu và audience sẵn; đó là yếu tố gây nhiễu lớn.

Roblox cũng xét mức độ người dùng hài lòng và tương tác sau khi vào chơi; metadata phải khớp nội dung thật. Tham khảo [Roblox Discovery](https://create.roblox.com/docs/discovery). Không quảng bá điểm mạnh chưa có trong gameplay chỉ để đổi lấy click.

## Kết luận để ra quyết định

**B là mẫu dễ đọc nhất trong ba ảnh ở 160px theo đánh giá hiện tại; A có tiềm năng thể hiện nét riêng tốt hơn nếu làm rõ quyết định; C cần giản lược.** Đây là thứ tự ưu tiên thử nghiệm, không phải thứ tự CTR đã đo. Mình không có quyền truy cập CTR/qPTR riêng của 12 game và chưa có kết quả personalization của One More Floor, nên không có cơ sở bảo đảm bất kỳ mẫu nào “cao nhất thị trường”.
