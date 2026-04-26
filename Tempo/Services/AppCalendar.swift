import Foundation

enum AppCalendar {
    static var current: Calendar {
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        return cal
    }
}
