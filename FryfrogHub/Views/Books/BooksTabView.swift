import SwiftUI

/// 书架 Tab：电子书 + 漫画 + 有声书 三分栏
struct BooksTabView: View {
    enum Section: String, CaseIterable {
        case ebooks = "电子书"
        case comics = "漫画"
        case audiobooks = "有声书"
    }

    @State private var section: Section = .ebooks

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("书架", selection: $section) {
                    ForEach(Section.allCases, id: \.self) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                switch section {
                case .ebooks:
                    EbookLibraryView()
                case .comics:
                    ComicLibraryView()
                case .audiobooks:
                    AudiobookLibraryView()
                }

                // 底部迷你播放器：任意分栏下都可继续收听
                AudiobookMiniPlayer()
            }
            .background(Color.appBackground)
            .navigationTitle("书架")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
