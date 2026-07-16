//
//  ScheduleEditorView.swift
//  Sorty
//
//  Sheet for creating or editing a scheduled organization entry
//

import SwiftUI

struct ScheduleEditorView: View {
    let folder: WatchedFolder
    let existingSchedule: ScheduleEntry?
    @EnvironmentObject var scheduler: FolderScheduler
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var frequency: ScheduleFrequency
    @State private var dayOfWeek: Int
    @State private var selectedTime: Date
    @State private var isEnabled: Bool

    init(folder: WatchedFolder, existingSchedule: ScheduleEntry? = nil) {
        self.folder = folder
        self.existingSchedule = existingSchedule

        let freq = existingSchedule?.frequency ?? .weekly
        _frequency = State(initialValue: freq)
        _dayOfWeek = State(initialValue: existingSchedule?.dayOfWeek ?? 1)
        _isEnabled = State(initialValue: existingSchedule?.isEnabled ?? true)

        var components = DateComponents()
        components.hour = existingSchedule?.hour ?? 9
        components.minute = existingSchedule?.minute ?? 0
        _selectedTime = State(initialValue: Calendar.current.date(from: components) ?? Date())
    }

    private var showsDayOfWeek: Bool {
        frequency == .weekly || frequency == .biweekly
    }

    private var showsDayOfMonth: Bool {
        frequency == .monthly
    }

    private var previewNextRun: Date {
        let hour = Calendar.current.component(.hour, from: selectedTime)
        let minute = Calendar.current.component(.minute, from: selectedTime)
        let entry = ScheduleEntry(
            folderId: folder.id,
            folderPath: folder.path,
            frequency: frequency,
            dayOfWeek: dayOfWeek,
            hour: hour,
            minute: minute,
            isEnabled: isEnabled
        )
        return scheduler.calculateNextRun(for: entry)
    }

    private static let weekdays = [
        (1, "Sunday"), (2, "Monday"), (3, "Tuesday"),
        (4, "Wednesday"), (5, "Thursday"), (6, "Friday"), (7, "Saturday")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .symbolEffect(.breathe, options: .speed(0.7), isActive: !reduceMotion)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(existingSchedule == nil ? "New Schedule" : "Edit Schedule")
                            .font(.headline)
                        Text(folder.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button("Save") {
                    HapticFeedbackManager.shared.success()
                    save()
                }
                .buttonStyle(.sortyProminent)
                .accessibilityIdentifier("SaveScheduleButton")
            }
            .padding()
            .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // Enabled toggle
                    ConfigSection(title: "Status", icon: "power", color: .green) {
                        Toggle(isOn: $isEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enabled")
                                    .font(.subheadline)
                                Text("Schedule will trigger automatically when enabled")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }

                    // Frequency
                    ConfigSection(title: "Frequency", icon: "repeat", color: .blue) {
                        Picker("Frequency", selection: $frequency) {
                            ForEach(ScheduleFrequency.allCases, id: \.self) { freq in
                                Text(freq.displayName).tag(freq)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: frequency) { _, newValue in
                            HapticFeedbackManager.shared.selection()
                            if newValue == .monthly {
                                dayOfWeek = min(dayOfWeek, 28)
                                if dayOfWeek < 1 { dayOfWeek = 1 }
                            } else if newValue == .weekly || newValue == .biweekly {
                                if dayOfWeek < 1 || dayOfWeek > 7 { dayOfWeek = 1 }
                            }
                        }
                    }

                    // Day selection
                    if showsDayOfWeek {
                        ConfigSection(title: "Day of Week", icon: "calendar", color: .orange) {
                            Picker("Day", selection: $dayOfWeek) {
                                ForEach(Self.weekdays, id: \.0) { value, name in
                                    Text(name).tag(value)
                                }
                            }
                            .onChange(of: dayOfWeek) { _, _ in
                                HapticFeedbackManager.shared.selection()
                            }
                        }
                    }

                    if showsDayOfMonth {
                        ConfigSection(title: "Day of Month", icon: "calendar", color: .orange) {
                            Picker("Day", selection: $dayOfWeek) {
                                ForEach(1...28, id: \.self) { day in
                                    Text("\(day)").tag(day)
                                }
                            }
                            .onChange(of: dayOfWeek) { _, _ in
                                HapticFeedbackManager.shared.selection()
                            }
                        }
                    }

                    // Time picker
                    ConfigSection(title: "Time", icon: "clock", color: .purple) {
                        DatePicker("Run at", selection: $selectedTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }

                    // Next run preview
                    ConfigSection(title: "Next Run", icon: "forward", color: .teal) {
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundStyle(.teal)
                                .contentTransition(.symbolEffect(.replace))
                            Text(previewNextRun, style: .date)
                                .font(.subheadline)
                                .numericTextTransition(animationValue: previewNextRun)
                            Text("at")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(previewNextRun, style: .time)
                                .font(.subheadline)
                                .numericTextTransition(animationValue: previewNextRun)
                        }
                    }

                    // Delete button for existing schedules
                    if existingSchedule != nil {
                        Button(role: .destructive) {
                            HapticFeedbackManager.shared.tap()
                            if let id = existingSchedule?.id {
                                scheduler.removeSchedule(id: id)
                            }
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Remove Schedule")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.sortyBordered)
                        .controlSize(.large)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 420, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
        .modalBounce()
    }

    private func save() {
        let hour = Calendar.current.component(.hour, from: selectedTime)
        let minute = Calendar.current.component(.minute, from: selectedTime)

        if var existing = existingSchedule {
            existing.frequency = frequency
            existing.dayOfWeek = dayOfWeek
            existing.hour = hour
            existing.minute = minute
            existing.isEnabled = isEnabled
            scheduler.updateSchedule(existing)
        } else {
            scheduler.addSchedule(
                for: folder,
                frequency: frequency,
                dayOfWeek: dayOfWeek,
                hour: hour,
                minute: minute
            )
        }
        dismiss()
    }
}
