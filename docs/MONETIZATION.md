# One More Floor: Monetization & Cash Sinks

## Đã triển khai (2026-10-23)

| Sản phẩm | Loại | Giá | Khoảnh khắc bán | Code |
|---|---|---|---|---|
| Extra Life (3 bậc theo độ sâu) | Product ×3 | 25 / 49 / 99 R$ | Màn bị loại (cửa sổ hồi sinh 10s, ván được giữ lại khi đang mua), màn Decision (mua trước), shop | `Config.ExtraLifeKey`, `Run:_awaitRevives`, `Run:HoldRevive` |
| Bless the Elevator | Product | 25 R$ | Khán giả: mọi người còn sống được +1 khiên, tên người mua hiện banner | `Run:Bless` |
| Curse the Elevator | Product | 25 R$ | Khán giả troll người còn sống | đã có |
| Golden Elevator | Product | 99 R$ | Shop: ×2 tiền cash-out cho **cả server** 15 phút, cộng dồn thời gian | thuộc tính `workspace.OMF_GoldenUntil/OMF_GoldenBy` |
| Cash Small / Medium / Large | Product ×3 | 49 / 149 / 399 R$ | Shop; số tiền = 1× / 3.6× / 12× túi điển hình ở tầng sâu nhất (`Config.CashPackAmount`) nên không bao giờ mất giá | `MonetizationService` |
| Starter Pack | Pass | 99 R$ | $5,000 + 3 Extra Life + 1 relic Rare, trao 1 lần | `grantStarter` |
| VIP | Pass | 149 R$ | +1 ô relic, túi tăng ×1,275 mỗi tầng thay vì ×1,25 (+10% phần tăng trưởng cơ bản), tag [VIP] vàng trong chat | đã có + tag |
| 2x Cash | Pass | 249 R$ | ×2 tiền khi ra | đã có |
| Lucky Bellhop | Pass | 199 R$ | +25% tỉ lệ relic, Relic Capsule rẻ hơn 20% | `EconomyService.RunStats` |
| Roblox Premium | Premium | — | +10% cash-out, nút mở Premium upsell | `PromptPremium` |

Chỗ tiêu cash mới (không trần): **Relic Polish** (nâng level relic bằng tiền, `Config.PolishCost`: $1.5k → $1.5M theo độ hiếm) và **Relic Capsule** (relic ngẫu nhiên, giá theo tầng sâu nhất, luôn hiện tỉ lệ `Rarity.Odds`, khóa theo `PolicyService.ArePaidRandomItemsRestricted`).

Sửa ngày 2026-10-26: receipt chỉ trả `PurchaseGranted` sau khi ProfileStore đã lưu PurchaseId (giữ 100 id gần nhất);
client gửi `ExtraLife2`/`ExtraLife3` cũng bị server định giá lại theo độ sâu; Extra Life đã mua (banked) chỉ tự
cứu khi túi > $0 (không tiêu phí lúc chẳng có gì để mất). Extra Life banked cứu tại chỗ trong arena; mua lúc đang
xem (spectator) thì hồi sinh vào cabin, 1 lần/ván.

Boss floor giờ luôn là boss (The Cube, The Eye). Icon cửa hàng: `assets/icons/*.png` (tạo bằng `make_icons.py`).
Id sản phẩm điền vào `Config.Products` / `Config.Passes` (0 = chưa tạo, UI hiện "COMING SOON").

Phần dưới đây là bản phân tích và đề xuất gốc (các mục chưa làm: Floor Pass, subscription, cosmetics, Express Ticket, prestige).

## 0. Vấn đề hiện tại

Túi tiền tăng theo cấp số nhân: ×1.25 mỗi tầng, ×1.5 ở tầng boss.

| Ra ở tầng | Túi (không relic/upgrade) |
|---|---|
| 5 | $277 |
| 10 | $1,600 |
| 15 | $6,751 |
| 20 | $25,923 |
| 25 | $96,439 |
| 30 | $354,985 |
| 40 | $4,770,925 |

Mua **toàn bộ** 6 nâng cấp tốn khoảng **$404k**, tức chỉ bằng một lần ra ở tầng 30. Sau 1–2 tuần, người chơi giỏi sẽ không còn gì để mua. Khi tiền mất giá trị thì quyết định "XUỐNG hay RA" cũng mất độ căng, mà đó là cốt lõi của game. Vì vậy game cần **chỗ tiêu tiền tăng theo cấp số nhân, không có trần**.

Nguyên tắc thiết kế:
1. **Bán khoảnh khắc, không bán chiến thắng.** Doanh thu cao nhất đến từ lúc người chơi sắp mất một túi tiền lớn, nên nên bán ở đúng khoảnh khắc đó.
2. **Daily Elevator giữ "sạch".** Ở chế độ này không có hồi sinh hay mua sức mạnh, để bảng xếp hạng Daily có uy tín (code đã chặn ExtraLife ở Daily).
3. **Người đã chết vẫn có việc để làm và để mua.** Khán giả ngồi rảnh, nên đây là cơ hội vừa cho tương tác xã hội vừa cho doanh thu.
4. **Mua đồ phải được người khác nhìn thấy**, vì đó là thứ tạo ra viral.

## 1. Người chơi tiêu tiền (cash) vào đâu

Các chỗ tiêu tiền được sắp theo vòng đời người chơi:

| Giai đoạn | Chỗ tiêu tiền | Ghi chú |
|---|---|---|
| Ngày 1 | **Nâng cấp** (đã có) | Giữ nguyên, rẻ, cho cảm giác tiến bộ ngay. |
| Ngày 1–3 | **Relic Slot** (đã có, max 2) | Thêm slot thứ 4 và 5 với giá rất cao ($250k, $2.5M). |
| Ngày 2+ | **Lost & Found Capsule**: máy quay relic trong lobby | Giá **tăng theo số lần đã quay** (ví dụ $500 × 1.15^n, reset mỗi ngày). Bắt buộc hiển thị tỉ lệ rơi (xem mục 4). |
| Ngày 2+ | **Relic Polish**: nâng cấp relic bằng tiền thay vì chờ rơi trùng | Level 2→5: $2k / $10k / $50k / $250k × hệ số độ hiếm. Đây là chỗ tiêu tiền vô hạn khi có 24 relic × 5 level. |
| Ngày 3+ | **Express Ticket**: bắt đầu ván ở tầng 5 / 10 / 15 | Giá bằng khoảng 60% giá trị túi tiêu chuẩn ở tầng đó. Người chơi lâu năm bỏ qua được các tầng dễ và nhàm. Chỉ có ở chế độ Normal. |
| Tuần 1+ | **Cosmetic shop xoay vòng hằng ngày** (bán bằng cash) | Trail, hiệu ứng khi bị loại, hiệu ứng khi ra, skin túi tiền, danh hiệu. Có 4 slot bán bằng cash, đổi mỗi 24h để tạo FOMO và lý do quay lại. |
| Tuần 2+ | **Renovation (Prestige)** | Reset nâng cấp và tiền để nhận +1 ⭐ khách sạn. Mỗi sao cho ×1.1 tiền khi ra, một danh hiệu, một màu đèn lobby riêng và mở khóa một theme tầng mới. Giá prestige tăng ×4 mỗi sao. |
| Mãi mãi | **Penthouse Plaque**: khắc tên lên tường danh dự trong lobby | $1M / $10M / $100M. Mọi người trong server đều thấy, là chỗ tiêu tiền chỉ để khoe. |

Đề xuất kèm theo: để tiền không bị lạm phát, nên cho **giá Capsule, Polish và Express tăng theo DeepestFloor** của người chơi. Như vậy người chơi mới không thấy mọi thứ quá đắt, còn người chơi lâu năm không thấy mọi thứ quá rẻ.

## 2. Robux: sản phẩm và gói

### 2.1 Sản phẩm theo khoảnh khắc (Developer Products), ưu tiên cao nhất

| Sản phẩm | Giá gợi ý | Khi nào hiện | Vì sao bán được |
|---|---|---|---|
| **Extra Life** (đã có) | 3 bậc giá: **25 / 49 / 99 R$** theo độ sâu (tầng 1–9 / 10–19 / 20+) | Màn bị loại hiện **ngay lập tức**: "Túi $96,439 của bạn sắp mất — HỒI SINH (5s)" | Người chơi sợ mất một túi tiền lớn. Mỗi ván chỉ hồi sinh 1 lần. |
| **Bag Insurance+** | 35 R$ | Ở màn Decision, ngay cạnh nút XUỐNG | Giữ 100% túi nếu chết ở tầng kế tiếp, giúp người chơi dám bấm XUỐNG. |
| **Blessing** (khán giả tặng) | 25 R$ | Ở màn khán giả, bấm vào một người còn sống | Tặng khiên cho bạn bè. Đây là hành vi xã hội tích cực, kiểu "bro cứu tao". |
| **Curse Elevator** (đã có) | 25 R$ | Ở màn khán giả | Troll người còn sống. Tên người mua hiện trên banner, tạo khoảnh khắc đáng quay clip. |
| **Golden Elevator** (boost toàn server) | **99 R$** | Nút trong shop, kèm thông báo toàn server | ×1.5 tiền cho **mọi người trong server** trong 15 phút, người mua được cảm ơn công khai. Cơ chế "server luck" này là một trong những sản phẩm bán chạy nhất năm 2025 (Grow a Garden và các game cùng dòng). |
| **Cash packs** (đã có) | 49 / 149 / 399 R$ | Shop | Giá trị gói nên **tăng theo DeepestFloor** (ví dụ bằng 2–3 lần túi trung bình của người chơi) để không bao giờ trở nên vô dụng. |

### 2.2 Game passes (mua một lần)

| Pass | Giá gợi ý | Nội dung |
|---|---|---|
| **Starter Pack** (chỉ trong 48h đầu, chỉ mua được 1 lần) | 99 R$ | $5k, 1 relic Rare chọn trước, trail "First Class", 3 Capsule miễn phí. Tỉ lệ chuyển đổi cao nhất cho người chơi mới. |
| **VIP** (đã có) | 149 R$ | +1 relic slot, +10% tăng trưởng túi, tag chat, sảnh VIP có quầy bar neon và chỗ đứng nhìn xuống shaft. |
| **Double Cash** (đã có) | 249 R$ (tăng từ 199) | ×2 tiền khi ra. |
| **Lucky Bellhop** | 199 R$ | +25% tỉ lệ rơi relic, Capsule rẻ hơn 20%. |
| **Elevator Remote** | 299 R$ | Tự chọn skin cabin cho cả nhóm khi bạn là người lên đầu tiên. Mọi người trong ván đều thấy. |

### 2.3 Subscription (Roblox Experience Subscriptions)

**Bellhop Club**, khoảng $4.99/tháng (mức giá nền tảng cho phép). Quyền lợi:
- Quà hằng ngày ×2.
- 1 lần hồi sinh miễn phí mỗi ngày (chỉ Normal mode).
- 1 Capsule miễn phí mỗi ngày.
- Mỗi tháng một cosmetic độc quyền.
- Huy hiệu tên màu vàng.

Doanh thu đều đặn, và quyền lợi hằng ngày kéo người chơi quay lại.

### 2.4 Floor Pass (season pass, 30 ngày)

- **Track miễn phí và track Premium (399 R$)**, kèm lựa chọn "+10 cấp" giá 199 R$.
- XP nhận từ: mỗi tầng qua được, tầng boss, nhiệm vụ ngày (ví dụ "qua 3 tầng boss", "ra với ≥$10k", "sống sót SpinBar 2 lần").
- Phần thưởng: cosmetic theo chủ đề season, Capsule, cash, danh hiệu, và hiệu ứng cabin ở cấp cuối.
- Đây là cơ chế giữ chân mạnh nhất trong danh sách, vì người chơi có mục tiêu 30 ngày.

### 2.5 Rewarded Video Ads (nếu game đủ điều kiện của Roblox)

- Xem quảng cáo để hồi sinh, giới hạn 1 lần mỗi ngày.
- Xem quảng cáo để nhân đôi quà hằng ngày.

Người chơi không trả Robux vẫn đóng góp doanh thu, và họ được trải nghiệm cảm giác hồi sinh. Sau đó họ dễ trả tiền cho lần hồi sinh tiếp theo hơn.

## 3. Cosmetic: thứ người khác nhìn thấy (động lực viral)

Mọi cosmetic đều làm bằng primitive, neon và VFX, đúng phong cách game. Có hai loại tiền:
- **Bán bằng cash:** phần lớn item thường.
- **Bán bằng Robux:** item hiếm và có hiệu ứng.

| Loại | Ai thấy | Ví dụ |
|---|---|---|
| **Elimination FX** | Cả cabin | Nổ thành đồng xu, tan thành pixel, "GAME OVER" neon. Vì người chơi chết rất nhiều, đây là cosmetic được nhìn thấy nhiều nhất. |
| **Cash-out Celebration** | Cả cabin + banner toàn server khi ≥$100k | Mưa tiền vàng, pháo hoa deco, tiếng chuông "ding" riêng. |
| **Trail** | Mọi người | Vệt neon theo màu độ hiếm. |
| **Bag skin** | Mọi người (túi lơ lửng trên đầu trong ván) | Vali, két sắt, bao tiền vàng, rương. Túi phình to theo giá trị. |
| **Cab skin** | Cả nhóm | Gỗ deco, tàu vũ trụ, lồng vàng, cabin kính. |
| **Title** | Bảng tên | "Floor 50 Diver", "Risk Addict", "Golden Bellhop". |

## 4. Tuân thủ chính sách Roblox (bắt buộc)

- **Paid random items**: Capsule là đồ ngẫu nhiên. Vì cash mua được bằng Robux, Capsule bị tính là đồ ngẫu nhiên trả tiền gián tiếp. Do đó cần:
  - **Hiển thị tỉ lệ rơi** ngay trên máy.
  - Gọi `PolicyService:GetPolicyInfoForPlayerAsync(player).ArePaidRandomItemsRestricted`, và nếu kết quả là true thì khóa Capsule cho người chơi đó (hoặc chỉ cho dùng Capsule miễn phí từ pass/season).
- Không dùng chữ "free" cho thứ cần Robux. Ghi giá Robux rõ trên nút. Không dùng countdown giả.
- Dùng công cụ **Price Optimization** trên Creator Dashboard để A/B test giá các developer product sau khi có lượng người chơi.

## 5. Lộ trình triển khai (theo hiệu quả/công sức)

| # | Hạng mục | Công | Hiệu quả kỳ vọng |
|---|---|---|---|
| 1 | Màn hồi sinh có giá theo độ sâu và countdown (dùng ExtraLife sẵn có, tách 3 product) | Thấp | ★★★★★ |
| 2 | Golden Elevator (boost toàn server) | Thấp | ★★★★★ |
| 3 | Starter Pack 48h | Thấp | ★★★★ |
| 4 | Blessing cho khán giả + nâng cấp Curse | Thấp | ★★★★ |
| 5 | Lost & Found Capsule + Relic Polish (chỗ tiêu tiền + tỉ lệ + PolicyService) | Trung bình | ★★★★ (giữ chân) |
| 6 | Express Ticket | Thấp | ★★★ |
| 7 | Cosmetic: Elimination FX, Trail, Cash-out (cửa hàng xoay vòng) | Trung bình | ★★★★ (viral) |
| 8 | Floor Pass season 1 | Cao | ★★★★★ (giữ chân + doanh thu) |
| 9 | Renovation (prestige) + Penthouse Plaque | Trung bình | ★★★ (chơi lâu dài) |
| 10 | Bellhop Club subscription | Thấp (sau khi có 7–8) | ★★★ |

Các KPI cần theo dõi (AnalyticsService đã gắn sẵn funnel):
- Tỉ lệ hiện màn hồi sinh → mua.
- Payer conversion ngày 1 / ngày 7.
- ARPDAU.
- Số dư cash trung bình theo DeepestFloor (để phát hiện lạm phát).
- Tỉ lệ chọn XUỐNG ở mỗi tầng: nếu chỉ số này giảm theo thời gian, tức là tiền đã mất giá trị.
