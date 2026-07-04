import SwiftUI
import AppKit

struct FooterView: View {
    @ObservedObject var service: QuotaService
    
    private var formattedRemainingTime: String {
        let sec = max(0, service.autoRefreshRemaining)
        if sec >= 60 {
            let m = sec / 60
            let s = sec % 60
            return s > 0 ? "\(m)m \(s)s" : "\(m)m"
        } else {
            return "\(sec)s"
        }
    }
    
    var body: some View {
        HStack {
            // Left: Auto refresh indicator
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.blue.opacity(0.8))
                    .frame(width: 5, height: 5)
                
                Text("Refreshes in \(formattedRemainingTime)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.8))
            }
            
            Spacer()
            
            // Settings Button
            Button(action: {
                if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                    appDelegate.openSettingsWindow()
                }
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray.opacity(0.9))
                    .padding(4)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Open Settings")
            
            // Quit Button
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .bold))
                    Text("Quit")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(Color(red: 0.95, green: 0.3, blue: 0.4))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(red: 0.95, green: 0.3, blue: 0.4).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(red: 0.95, green: 0.3, blue: 0.4).opacity(0.3), lineWidth: 0.5)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.2))
    }
}
