import SwiftUI

struct EditView: View {
    @Binding var text: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Entry")
                .font(.headline)
            
            TextEditor(text: $text)
                .font(.custom("Roboto", size: 14))
                .padding(4)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
                .frame(minHeight: 200)
            
            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                
                Button("Save") {
                    onSave(text)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 500, height: 400)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
    }
}
