//
//  ToastView.swift
//  Clipy
//
//  Created by repon kumar roy on 15.11.2025.
//

import SwiftUI
import Combine

struct ToastView: View {
    let message: String
    
    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.8))
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

class ToastManager: ObservableObject {
    @Published var message: String?
    private var task: Task<Void, Never>?
    
    @MainActor
    func show(_ message: String) {
        task?.cancel()
        withAnimation(.spring()) {
            self.message = message
        }
        
        task = Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut) {
                self.message = nil
            }
        }
    }
}
