# Đánh giá One More Floor — 25/10/2026

## Kết luận

Game có một vòng chơi đáng phát triển: **sống sót → túi tiền lớn hơn → ra về hay xuống tiếp → có thể mất túi**. Điểm khác biệt đáng quảng bá nhất là quyết định mạo hiểm này, cộng với việc người bị loại vẫn được bỏ phiếu lời nguyền. Chỉ quảng bá “thang máy và nhiều minigame” sẽ bỏ phí hai đặc điểm đó.

Đánh giá chủ quan ở giai đoạn hiện tại: **khoảng 7/10 về mức độ hoàn thiện sản phẩm**. Đây không phải dự báo doanh thu hoặc retention. Điểm mạnh là nội dung, cấu trúc mã và nhận diện lobby; điểm yếu hiện rõ là cách trình bày sản phẩm, khả năng đọc trên điện thoại dọc và một số hợp đồng gameplay/mua hàng chưa nhất quán.

| Mặt đánh giá | Nhận định |
|---|---|
| Ý tưởng cốt lõi | Mạnh: tiền đang có tạo lý do cụ thể để sợ chết và cân nhắc xuống tiếp |
| Nội dung | Khá tốt: 18 thử thách thường, 2 boss; nhiều loại kỹ năng khác nhau |
| Nhận diện hình ảnh | Có bản sắc: Midnight Deco, cửa thang máy, đồng hồ tầng, cyan/magenta/brass |
| Cửa hàng | Cần đầu tư: biểu tượng nhỏ, ít thể hiện vật phẩm, metadata nhiều sản phẩm dùng chung ảnh |
| Mobile | Có layout thích ứng; màn dọc vẫn thu nhỏ shop thay vì tổ chức lại nội dung đủ lớn |
| Tiến trình dài hạn | Có nền móng, nhưng các nâng cấp và relic đều có trần |
| Kỹ thuật | Biên dịch và dựng arena tốt trong phạm vi kiểm tra; còn rủi ro receipt và luật sản phẩm cần xử lý |
| Khả năng thu hút người chơi | Có chất liệu tốt để làm thumbnail; chưa có analytics để kết luận hiệu quả thực tế |

## Phạm vi và bằng chứng

- Kiểm kê toàn bộ cây dự án, cấu hình Rojo/Wally, tài liệu, assets, archive và 69 file Luau trong `src`, tổng 23.988 dòng.
- Đọc sâu cấu hình gameplay, economy, lưu dữ liệu, monetization, run state machine, chọn thử thách, UI shop, responsive layout, onboarding và analytics. Quét metadata/cấu trúc của toàn bộ 20 thử thách; không coi đây là security audit từng dòng của mọi module.
- Biên dịch **69/69 file thành công** bằng `luau-compile --null`. Đây là kiểm tra cú pháp/biên dịch, không thay thế type analysis hay test hành vi.
- Dùng Studio đang kết nối: place `139070842708870`, universe `10772257156`, tên place hiện trả về là `Test`.
- Dựng từng thử thách tại `max(MinFloor, 1)` và tầng 30: **40/40 lượt thành công, không rơi vào arena dự phòng**. Các lượt dựng này không có người chơi, không chạy toàn bộ `Start`/`Judge`, nên chưa xác nhận reachability, chiến thắng, va chạm hoặc cân bằng.
- Quan sát lobby, shop desktop, shop iPhone 13 ngang/dọc, Jump Rope B1 và The Eye B10. B10 dùng công cụ force floor và god mode chỉ trong server thử nghiệm để xem hình ảnh.
- Profile thử nghiệm có `OMF_MockData = true` sẵn từ trước. Tài khoản thử nghiệm sở hữu các pass, nên lượt chơi này không đại diện cho người mới hoàn toàn không có sức mạnh.
- Đọc metadata đủ 9 developer product và 4 pass bằng MarketplaceService, không thực hiện giao dịch. Giá là ảnh chụp tại thời điểm kiểm tra/tài khoản kiểm tra, có thể đổi sau này.
- Đã dừng playtest. Force challenge/start floor/god mode chỉ được đặt trong runtime; không sửa source gameplay hay publish place.
- Chưa có dữ liệu Creator Analytics về CTR, qPTR, retention, doanh thu hoặc acquisition. Chưa test multiplayer 8 người, reconnect, receipt thật, crash recovery hay hiệu năng trên máy điện thoại thật.

## Điểm mạnh cần giữ

**Tiền là một phần gameplay.** `Run:_results` cộng thưởng rồi nhân túi; `Run:_cashOut` mới chuyển thành tiền lưu. Điều này tạo câu chuyện dễ hiểu cho thumbnail: một người đang ôm thành quả trước một tầng nguy hiểm.

**Khán giả có vai trò.** Người bị loại có thể ở lại quan sát, bỏ phiếu curse và dùng Bless/Curse. Đây là chất liệu tốt cho nhóm bạn và video phản ứng. Tác động curse nhắm tới tầng tiếp theo; hình quảng bá cần giữ đúng quan hệ đó.

**Nội dung đủ để thử phát hành.** Các thử thách gồm di chuyển/né tránh, trí nhớ, câu hỏi, tranh ô, mê cung, đối kháng và boss. Không cần thêm hàng loạt minigame trước khi kiểm chứng onboarding và việc người chơi có hiểu DEEPER/LEAVE hay không.

**Hệ thống có cấu trúc để mở rộng.** ChallengeRegistry, Context, tách client/server/shared, rate limit và ProfileStore là nền móng tốt. Cả 20 arena dựng được tại hai mức độ sâu là tín hiệu tích cực về tính toàn vẹn hiện tại.

**Nhận diện sẵn có đáng tái sử dụng.** Hai cửa cyan/magenta, đồng hồ tầng và brass trên nền mực đen có thể thành bộ dấu hiệu riêng. Giữ các hình khối đơn giản/neon của arena trong hình quảng bá để người chơi nhận ra game sau khi bấm vào.

## Những việc nên xử lý trước chiến dịch thu hút người chơi

| Ưu tiên | Phát hiện và bằng chứng | Hành động đề xuất |
|---|---|---|
| P0 | 9 developer product cùng trả về `IconImageAssetId = 88963008124478`; 4 pass cùng trả về `133448903949274`. Trong repo có 13 PNG riêng nhưng metadata Roblox chưa phân biệt từng sản phẩm | Gán icon theo từng product/pass; kiểm lại metadata và hình thực tế sau moderation/cache |
| P0 | Shop dùng `Kit.Icon`, có hình chỉ 26×26 virtual px (`Panels.luau:1586`); chưa có đường gán bộ PNG sản phẩm vào thẻ này | Thêm registry ảnh sản phẩm riêng và khung ảnh đủ lớn. Icon điều hướng vẫn giữ hệ vector hiện tại |
| P0 | Shop dọc trên iPhone 13 vẫn có ba pass cạnh nhau, phần mô tả rất nhỏ. Runtime ghi viewport 389×762, scale 0,5; `Screen.luau:56` chặn scale thấp nhất 0,5 | Đổi shop dọc sang 1 cột, tăng chữ và hit target; kiểm tra cuộn tới các gói phía dưới. Không giải quyết chỉ bằng vẽ ảnh nhiều chi tiết hơn |
| P1 | VIP ghi “+10% bag growth” (`Panels.luau:1462`), trong khi `EconomyService.luau:47` cộng `0,1 × (1,25 − 1) = 0,025` vào multiplier. Tầng thường thành ×1,275 trước các bonus khác | Mô tả rõ “+10% phần tăng trưởng cơ bản” hoặc diễn đạt trực tiếp multiplier. Không vẽ huy hiệu khiến người mua hiểu là +10 điểm % hoặc nhân toàn túi ×1,1 |
| P1 | `_addMember` luôn gọi `EconomyService.RunStats` (`Run.luau:142`), bao gồm relic, upgrade và VIP/Lucky; Daily chỉ chặn một số giao dịch, không chuẩn hóa loadout | Nếu muốn cạnh tranh cùng sức mạnh, đặt loadout cố định cho Daily. Nếu giữ tiến trình cá nhân, diễn đạt Daily là cùng seed, chưa quảng bá “công bằng tuyệt đối” |
| P1 | `_trySave` tiêu ExtraLives khi còn hàng trong Normal nhưng không đánh dấu `ExtraLifeUsed` (`Run.luau:933`); `TryRevive` mới đánh dấu một lần. Shop nói quay về cab, trong khi banked save gọi `_rescue` trở lại arena | Chốt rõ hai cơ chế: tự cứu tại arena và hồi sinh từ spectator; đồng bộ mô tả, giới hạn, UI và hình minh họa |
| P1 | `processReceipt` cập nhật bảng profile trong RAM, ghi PurchaseId rồi trả `PurchaseGranted`; chưa thấy chờ xác nhận save bền vững (`MonetizationService.luau:90–123`). Lịch sử giữ 50 receipt | Review luồng xác nhận lưu theo ProfileStore trước khi xác nhận receipt, gồm crash/retry. Đây là rủi ro suy ra từ code, chưa tái hiện mất giao dịch; cắt lịch sử 50 ID cũng cần được xem xét trong thiết kế idempotency |
| P1 | Chỉ key `ExtraLife` được resolve theo độ sâu; client gửi trực tiếp `ExtraLife2`/`ExtraLife3` sẽ đi qua (`MonetizationService.luau:194`) | Chuẩn hóa mọi alias của Extra Life về một ý định mua và chọn tier ở server. Đây là lỗ hổng quy tắc giá suy ra từ code, chưa thử mở prompt mua |
| P2 | Meta hiện có trần: 6 upgrade có max; 24 relic max level 5 (`Config.luau:80`); Capsule có thể tiếp tục mua nhưng khi hoàn tất bộ sưu tập không tạo tiến trình mới | Ưu tiên một lớp cosmetic/danh hiệu mục tiêu dài hạn sau khi có dữ liệu retention; không gọi Polish là sink vô hạn |
| P2 | `FloorCleared` hiện gắn custom field là mode, còn `Eliminated` gắn challenge ID | Thêm event bắt đầu thử thách cùng ID/floor/mode/cohort để có mẫu số tính tỷ lệ chết theo thử thách; log thời gian tới boarding, lựa chọn Deeper/Leave, hiện offer và mở prompt |
| P2 | Các badge ID vẫn bằng 0; HANDOFF nói product ID = 0 và liệt kê nhiều thử thách đã vào archive, không còn đúng với code | Cập nhật tài liệu và badge trước launch; kiểm tra tên game hiển thị trên trang công khai vì Studio hiện có tên `Test` |
| P2 | Log có cảnh báo lặp `203785492: Asset type does not match requested type`; chưa tìm thấy reference trong các trường ảnh/texture phổ biến của edit DataModel | Truy tiếp nguồn cảnh báo, phân biệt asset trong game và plugin Studio; chưa đủ bằng chứng để quy cho script gameplay |

## Nhịp chơi và kinh tế

Một tầng thường có 4s xuống thang + 3,5s briefing + khoảng 20–28s thử thách + 2,5s kết quả + tối đa 8s quyết định. Tổng thường khoảng **38–46s**, có thể ngắn hơn khi mọi người chọn sớm hoặc challenge kết thúc sớm. Boss có cửa hàng và thời gian quyết định dài hơn. Đây là nhịp đủ để tạo cảm giác “thêm một tầng nữa”, nhưng cần đo thời gian người mới đến thử thách đầu và ra tiền lần đầu.

Túi chuẩn theo đúng công thức hiện tại, không pickup, không pass/relic/upgrade:

| Tầng hoàn thành | Túi |
|---|---:|
| 1 | $18 |
| 3 | $90 |
| 5 | $277 |
| 10 | $1.600 |
| 20 | $25.923 |
| 30 | $354.985 |
| 40 | $4.770.925 |

Mua tối đa toàn bộ 6 nâng cấp tốn **$404.171**. Vì vậy tầng sâu và các multiplier cash-out có thể làm tiến trình upgrade kết thúc nhanh; việc bao nhiêu người thực sự tới được các tầng đó chưa biết. Capsule và cash pack cũng dừng scale theo độ sâu ở 40 trong Config, nên tuyên bố “không bao giờ mất giá” trong tài liệu là quá rộng.

Nên đo trước khi đổi balance: phân bố tầng kết thúc, số lần cash-out, tỷ lệ chọn xuống tiếp theo giá trị túi, thời gian mua upgrade đầu tiên và tỷ lệ người đạt max. Không đổi kinh tế chỉ từ một bảng tăng trưởng lý thuyết.

## Kết quả dựng thử thách

Mỗi hàng đã dựng tại tầng thấp nhất dùng cho smoke test và tầng 30. Số part dưới đây là **BasePart có ngay sau Build ở tầng 30**, chưa gồm toàn bộ hazard/FX sinh trong Start, cab, lobby hoặc người chơi; không phải số đo hiệu năng.

| Thử thách | Zone | Part tại B30 |
|---|---:|---:|
| BossEye | Boss | 95 |
| BossSlam | Boss | 32 |
| GlassBridge | 2 | 256 |
| HauntedMaze | 2 | 332 |
| HoleInWall | 1 | 53 |
| HotPotato | 2; cần 2 người khi chơi thật | 49 |
| JumpRope | 1 | 45 |
| LavaRise | 3 | 85 |
| LayerDrop | 2 | 180 |
| MemoryTiles | 1 | 109 |
| NeonSnake | 3 | 48 |
| PaintParty | 3 | 224 |
| PopQuiz | 1 | 56 |
| RedLight | 1 | 58 |
| RushHour | 1 | 359 |
| ShellGame | 1 | 117 |
| SimonSays | 2 | 82 |
| Spotlight | 3 | 62 |
| VaultRun | 2 | 122 |
| WindTunnel | 2 | 184 |

Nên đưa RushHour, HauntedMaze và GlassBridge vào lượt profile nhiều người tiếp theo vì Build có nhiều part hơn trong mẫu này. Chưa có dữ liệu CPU/GPU/network để kết luận chúng chậm. `StreamingEnabled = false` và hỗ trợ nhiều run song song khiến kiểm tra nhiều arena cùng lúc quan trọng hơn một arena đơn lẻ.

## Thứ tự thực hiện

1. Chốt quyền lợi VIP/Extra Life/Daily; xử lý review receipt và chuẩn hóa tier sản phẩm.
2. Cải thiện shop mobile và thêm đường hiển thị ảnh sản phẩm trong game.
3. Làm bộ icon và ba thumbnail theo [kế hoạch thiết kế](ICON_THUMBNAIL_PLAN.vi.md); gán riêng trên Roblox.
4. Test 2–8 người: vào thang, chết, bỏ phiếu, Bless/Curse, hồi sinh, cash-out, disconnect và join lại.
5. Thu baseline analytics, chạy thử hình ảnh, rồi quyết định có cần thêm nội dung/tiến trình.

CTR cao không bảo đảm người chơi ở lại. Roblox cũng xét mức chơi có ý nghĩa và early bounce; vì vậy thumbnail phải khớp trải nghiệm sau khi vào game. Xem [Discovery](https://create.roblox.com/docs/discovery) và [Thumbnails](https://create.roblox.com/docs/production/publishing/thumbnails).
