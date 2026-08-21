import SwiftUI

struct HeaderView: View {

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
            Text("TokenMeter")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }
}
