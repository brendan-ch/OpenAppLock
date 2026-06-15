//
//  DayOfWeekPicker.swift
//  OpenAppLock
//

import SwiftUI

/// Seven circular day toggles (S M T W T F S) using system colors, meant to
/// sit inside a Form/List row. The day-set summary is shown by the enclosing
/// section header.
struct DayOfWeekPicker: View {
    @Binding var days: Set<Weekday>

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Weekday.displayOrder, id: \.self) { day in
                dayToggle(day)
            }
        }
    }

    private func dayToggle(_ day: Weekday) -> some View {
        let isOn = days.contains(day)
        return Button {
            if isOn {
                days.remove(day)
            } else {
                days.insert(day)
            }
        } label: {
            Text(day.shortLabel)
                .font(.subheadline.weight(.semibold))
                // Keep the circle a fixed size so all seven always fit one row;
                // let the letter shrink to fit instead of clipping at large
                // Dynamic Type sizes.
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(isOn ? Color.white : Color.secondary)
                .frame(width: 38, height: 38)
                .background(
                    isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.tertiarySystemFill)),
                    in: Circle()
                )
                // Each cell takes an equal share of the row and at least a
                // 44pt-tall hit area, so the whole strip is comfortably tappable.
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("dayToggle-\(day.rawValue)")
        .accessibilityLabel(day.abbreviation)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

#Preview {
    @Previewable @State var days = Weekday.weekdays
    Form {
        Section {
            DayOfWeekPicker(days: $days)
        } header: {
            HStack {
                Text("On these days").textCase(nil)
                Spacer()
                Text(days.summary).textCase(nil)
            }
        }
    }
}
