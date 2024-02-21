//
//  PoemView.swift
//  Wuserade
//
//  Created by Астемир Бозиев on 16.02.2024.
//

import SwiftUI
import Pow

struct PoemView: View {
    @State var isLiked = false
    @State private var textViewheight: CGFloat = 0

    var poem: Poem

    init(poem: Poem) {
        self.poem = poem
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .center) {
                PoemHeader()
                HStack {
                    SelectableTextView( text: poem.content, fontSize: 18, height: $textViewheight)
                    .frame(height: textViewheight)
                    Spacer()
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    HapticManager.shared.impact(style: .heavy)
                    withAnimation {
                        isLiked.toggle()
                    }
                } label: {
                    if isLiked {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                            .transition(
                                .movingParts.pop(.red)
                            )
                    } else {
                        Image(systemName: "heart")
                            .foregroundStyle(.primary)
                            .transition(.identity)
                    }
                }
            }
        }
    }

    private func PoemHeader() -> some View {
        VStack(alignment: .center) {
            Text(poem.title)
                .font(.title)
                .fontDesign(.serif)
                .multilineTextAlignment(.center)
            Text(poem.author.name)
                .italic()
                .fontDesign(.serif)
            Divider()
        }
        .padding(.bottom, 10)
    }
}

struct SelectableTextView: UIViewRepresentable {
    var text: String
    var fontSize: CGFloat
    var isEditable: Bool = false
    var isSelectable: Bool = true
    @Binding var height: CGFloat


    init(text: String, fontSize: CGFloat, height: Binding<CGFloat>) {
        self.text = text
        self.fontSize = fontSize
        self._height = height
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = isEditable
        textView.isSelectable = isSelectable
        textView.text = text
        textView.isUserInteractionEnabled = true
        textView.font = UIFont.systemFont(ofSize: fontSize)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text
        uiView.font = UIFont.systemFont(ofSize: fontSize)
        DispatchQueue.main.async {
            self.height = uiView.contentSize.height
        }

    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: SelectableTextView

        init(_ parent: SelectableTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            DispatchQueue.main.async {
                self.parent.height = textView.contentSize.height
            }
        }
    }
}

#Preview {
    NavigationStack {
        PoemView(poem: Poem.example)
        .tint(.primary)
    }
}
