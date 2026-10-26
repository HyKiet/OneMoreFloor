# One More Floor — artwork v3

Bộ icon thay thế hướng render 3D v2, bám thư viện `icons/` theo yêu cầu ngày 25/10/2026: viền navy đậm, mảng màu cel shading, highlight sắc và PNG có nền trong suốt thật.

## File sử dụng

- `icons/`: 13 file product/pass 512×512, thêm `GameIcon.png` 512×512; đều RGBA trong suốt.
- `ui256/`: cùng bộ ở 256×256 cho giao diện.
- `small64/`: cùng bộ ở 64×64.
- `thumbnails/`: A Risk, B Cube, C Curse, JPEG 1920×1080, mỗi file dưới 3MB. Thumbnail có bối cảnh; yêu cầu bỏ nền được áp dụng cho icon.
- `previews/product-icons-overview.jpg`: bảng toàn bộ icon. Nền caro trong ảnh preview chỉ phục vụ kiểm tra, không nằm trong file icon.
- `previews/reference-vs-v3.jpg`: mẫu gốc và bản dùng cho game đặt cạnh nhau.
- `previews/light-dark-64px.jpg`: kiểm tra trên nền sáng/tối ở 64px thật.
- `previews/thumbnails-overview.jpg`: so ba thumbnail ở kích thước lớn, 320px và 160px.
- `source/`: ảnh nguồn giữ nguyên, không ghi đè thư viện gốc; không đưa vào ZIP.
- `prompts/generation-log.json`: prompt đầy đủ, ảnh tham chiếu, nguồn và route.
- `manifest.json`: mapping product key, commerce ID, artwork nguồn, đường dẫn export và Image ID do người dùng cung cấp.
- `roblox_asset_ids.json`: đủ 14 Image ID trong ảnh Asset Manager ngày 25/10/2026.
- `studio_validation.json`: bằng chứng preload, render thật của 14 ảnh và binding ba tier Extra Life.
- `validation.json`: alpha, kích thước, lề an toàn vòng tròn, dung lượng và SHA-256 từng icon.

## Cách bám phong cách

Lấy trực tiếp Heart, Shield, Golden Coin và Crown bản 1st Outline trong thư viện làm tham chiếu, thay vì dùng lại artwork 3D bị từ chối. Màu viền ở cả bốn mẫu là RGB (4,4,53), hex #040435. Giữ vài mặt sáng–tối lớn, không thêm nền navy, bokeh, bóng studio, tia sáng hoặc viền trắng ngoài.

Artwork mới: Extra Life, Bless, Curse, Golden Elevator, Double Cash, Lucky Bellhop, icon game và ba thumbnail. Các ảnh mới dùng `image_gen` tích hợp; công cụ không công bố tên model. Nền trong suốt lấy trực tiếp từ công cụ, không tẩy bằng color key.

Artwork tái sử dụng nguyên hình từ thư viện người dùng: VIP dùng Crown; Starter Pack dùng Purple Gift; ba cash pack dùng PileCoins, BagCoins và VaultCoins. Việc tái sử dụng giúp giữ nguyên nét của mẫu, không nhận là artwork tự vẽ mới. Crown/Gift có nguồn gốc 256px; bản upload 512px là upscale, bản UI256 giữ độ phân giải phù hợp.

Ba Extra Life có cùng quyền lợi và chỉ khác bậc giá, nên chủ ý dùng chung một artwork. Phân biệt B1–9, B10–19 và B20+ bằng tên sản phẩm/nhãn UI. Bộ có 13 file sản phẩm và 11 artwork sản phẩm khác nhau.

Ảnh nguồn thumbnail do công cụ trả về khoảng 1672×941; bản giao được chuẩn hóa/crop rất nhẹ sang 1920×1080. Không phải render nguồn 4K hoặc file vector. Thumbnail là minh họa gameplay, không phải screenshot nguyên bản.

## Kiểm tra và dùng trong Roblox

Exporter chỉ đăng ký vị trí, resize bằng alpha premultiplied, tạo preview và đóng ZIP; không vẽ artwork. Cả bộ icon có pixel alpha 0 ở mép và bốn góc, có vùng opaque thực, và phần hình được đặt trong vùng an toàn khi crop tròn. Kiểm tra định lượng không chứng minh style khớp tuyệt đối hoặc CTR tăng; cần xem preview và thử nghiệm với người chơi.

Giữ giá, tên và thời hạn ở UI. Không dùng commerce/product ID làm ImageLabel asset ID. Người dùng đã upload ảnh và cung cấp ID; bộ này đã nối vào source UI qua `src/shared/Images.luau`, đồng bộ vào Studio bằng Rojo. Shop hiển thị ảnh sản phẩm, Starter Pack và Golden Elevator; header dùng GameIcon; Decision/Spectator/revive dùng ảnh Extra Life theo tier, Bless và Curse. Cả 14 ảnh đã preload Success và render IsLoaded=true trong client. Chưa đổi ảnh của product/pass hoặc icon trang game trên Creator Dashboard, và chưa publish place lên live servers.

Thư viện gốc Free Icon Pack của @gvesster: giữ điều kiện trong `SOURCE_ICON_LICENSE.txt`, bản gốc tại `icons/License.txt`. Các artwork lấy từ thư viện được dùng cho game này; ZIP là gói bàn giao dự án, không phải asset pack để bán lại.

Tái tạo export và ZIP: `python assets/marketing/v3/export_assets.py` từ thư mục dự án.
