// 開発者のアプリに入る本体。iOS のみ。
// macOS でビルドしたときは中身が空になる（Mac 版は GeoFakeWire だけを使う）。
//
// 中身はすべて `#if DEBUG` の中にある。Swift Package は、アプリの構成の「名前」に
// Debug が入っているときだけ DEBUG 付きでビルドされる（Xcode の決まり）。
// Staging のような名前の構成では、debug 型でも GeoFake は空になる。README を参照。

#if os(iOS)
import Foundation

public enum GeoFake {
    /// GeoFake の版。hello で Mac に伝える
    public static let version = "3.0.0"

    /// 起動時に1回呼ぶ。Mac から方位とモーションを受けて、アプリの delegate / handler に渡すようになる。
    /// 2回目以降の呼び出しは何もしない。
    @MainActor
    public static func start() {
        #if DEBUG
        GFCore.shared.start()
        #endif
        // DEBUG の無い構成（Release、DEBUG を立てていない Staging など）では何もしない。
        // 実行ファイルに文字列を残さないため、案内の表示もしない

    }
}
#endif
