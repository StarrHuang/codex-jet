import SwiftUI

struct LanguagePicker: View {
    @AppStorage("appLanguage") private var selection = "system"
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "globe").foregroundStyle(.secondary)
            Picker(L("语言"), selection: $selection) {
                Text(L("跟随系统")).tag("system")
                Text("中文").tag("zh-Hans")
                Text("English").tag("en")
            }.pickerStyle(.menu).labelsHidden().font(.system(size: 11))
        }
    }
}
