import SwiftUI

struct HeaderView: View {
    @ObservedObject var service: QuotaService
    @State private var pulseOpacity: Double = 0.5
    @State private var rotationAngle: Double = 0.0
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // App Icon Badge
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.3, green: 0.2, blue: 0.9), Color(red: 0.0, green: 0.8, blue: 0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                    .shadow(color: Color(red: 0.0, green: 0.8, blue: 0.9).opacity(0.4), radius: 6, x: 0, y: 2)
                
                Image(systemName: "cpu.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // Title
            HStack(spacing: 6) {
                Text("TokenMeter")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                
                Circle()
                    .fill(service.errorMessage == nil ? Color.green : Color.red)
                    .frame(width: 7, height: 7)
                    .opacity(pulseOpacity)
                    .shadow(color: (service.errorMessage == nil ? Color.green : Color.red).opacity(0.6), radius: 4, x: 0, y: 0)
                    .onAppear {
                        withAnimation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                            pulseOpacity = 1.0
                        }
                    }
            }
            
            Spacer()
            
            // Refresh Button
            Button(action: {
                Task {
                    await service.refresh()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.06))
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black.opacity(0.7))
                        .rotationEffect(.degrees(service.isLoading ? 360 : 0))
                        .animation(
                            service.isLoading
                            ? Animation.linear(duration: 1.0).repeatForever(autoreverses: false)
                            : .default,
                            value: service.isLoading
                        )
                }
            }
            .buttonStyle(PlainButtonStyle())
            .help("Refresh Quota Now")
            .disabled(service.isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }
}
