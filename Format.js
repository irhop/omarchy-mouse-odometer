// ---------------------------------------------------------------------------
// Format.js — turning the tracker's state file into things worth reading.
// The daemon stores metres; everything user-facing is derived here so the bar
// label and the panel can never disagree about what a number means.
// ---------------------------------------------------------------------------

var METRE_PER_FOOT = 0.3048
var FEET_PER_MILE = 5280
var METRE_PER_INCH = 0.0254

function emptyBucket() {
  return { meters: 0, counts: 0, clicks: 0, scrolls: 0, active_seconds: 0 }
}

function parseState(raw) {
  if (!raw || raw.trim() === "") return null
  try {
    var parsed = JSON.parse(raw)
    if (!parsed || typeof parsed !== "object") return null
    parsed.days = parsed.days || {}
    parsed.total = parsed.total || emptyBucket()
    parsed.devices = parsed.devices || {}
    return parsed
  } catch (e) {
    return null
  }
}

function dayKey(date) {
  var month = date.getMonth() + 1
  var day = date.getDate()
  return date.getFullYear() + "-" + (month < 10 ? "0" : "") + month + "-" + (day < 10 ? "0" : "") + day
}

function bucket(state, key) {
  if (!state || !state.days) return emptyBucket()
  var found = state.days[key]
  return found ? found : emptyBucket()
}

function todayBucket(state, today) {
  return bucket(state, dayKey(today || new Date()))
}

// Last `count` days, oldest first, each carrying its own date so the chart
// can label columns without recomputing the calendar.
function recentDays(state, count, reference) {
  var out = []
  var today = reference || new Date()
  for (var offset = count - 1; offset >= 0; offset--) {
    var date = new Date(today.getFullYear(), today.getMonth(), today.getDate() - offset)
    var key = dayKey(date)
    var day = bucket(state, key)
    out.push({
      key: key,
      date: date,
      meters: Number(day.meters) || 0,
      clicks: Number(day.clicks) || 0,
      scrolls: Number(day.scrolls) || 0,
      activeSeconds: Number(day.active_seconds) || 0,
      isToday: offset === 0
    })
  }
  return out
}

function sumMeters(days) {
  var total = 0
  for (var i = 0; i < days.length; i++) total += days[i].meters
  return total
}

// Yesterday and back — today is a partial day and would drag any average it
// joined downwards, which would flatter you for no reason.
function averageMeters(days, excludeToday) {
  var counted = 0, total = 0
  for (var i = 0; i < days.length; i++) {
    if (excludeToday && days[i].isToday) continue
    total += days[i].meters
    counted++
  }
  return counted > 0 ? total / counted : 0
}

function distance(meters, units) {
  meters = Number(meters) || 0
  if (units === "imperial") {
    var feet = meters / METRE_PER_FOOT
    if (feet >= FEET_PER_MILE) return (feet / FEET_PER_MILE).toFixed(2) + " mi"
    if (feet >= 1) return Math.round(feet) + " ft"
    return Math.round(meters / METRE_PER_INCH) + " in"
  }
  if (meters >= 1000) return (meters / 1000).toFixed(2) + " km"
  if (meters >= 1) return Math.round(meters) + " m"
  return Math.round(meters * 100) + " cm"
}

// Short enough to sit in a 26px bar without pushing the clock around.
function compactDistance(meters, units) {
  meters = Number(meters) || 0
  if (units === "imperial") {
    var feet = meters / METRE_PER_FOOT
    if (feet >= FEET_PER_MILE) return (feet / FEET_PER_MILE).toFixed(1) + "mi"
    return Math.round(feet) + "ft"
  }
  if (meters >= 1000) return (meters / 1000).toFixed(1) + "km"
  return Math.round(meters) + "m"
}

function count(value) {
  var n = Math.round(Number(value) || 0)
  var text = String(n)
  var out = ""
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 === 0) out += ","
    out += text.charAt(i)
  }
  return out
}

function duration(seconds) {
  seconds = Math.round(Number(seconds) || 0)
  if (seconds >= 3600) {
    var hours = Math.floor(seconds / 3600)
    var minutes = Math.floor((seconds % 3600) / 60)
    return hours + "h " + (minutes < 10 ? "0" : "") + minutes + "m"
  }
  if (seconds >= 60) return Math.floor(seconds / 60) + "m"
  return seconds + "s"
}

// "+18%" / "-9%" against a baseline, or "" when there is nothing to compare to.
function deltaText(value, baseline) {
  if (!baseline || baseline <= 0) return ""
  var percent = Math.round((value / baseline - 1) * 100)
  return (percent >= 0 ? "+" : "") + percent + "%"
}

function weekdayLetter(date) {
  return ["S", "M", "T", "W", "T", "F", "S"][date.getDay()]
}

function shortDate(date) {
  return Qt.formatDate(date, "ddd d MMM")
}

// Metres per hour of hands-on-mouse time: the number that actually reflects
// technique, since it does not punish you for a long day at the desk.
function metersPerActiveHour(day) {
  if (!day || !day.activeSeconds) return 0
  return day.meters / (day.activeSeconds / 3600)
}

// --- Series for the sparklines ---------------------------------------------

// The last `count` hours ending with the one in progress, walking back across
// midnight into yesterday's bucket where needed.
function hourlySeries(state, count, reference) {
  var out = []
  var now = reference || new Date()
  for (var offset = count - 1; offset >= 0; offset--) {
    var slot = new Date(now.getFullYear(), now.getMonth(), now.getDate(), now.getHours() - offset)
    var day = bucket(state, dayKey(slot))
    var hours = day.hours || {}
    out.push({
      date: slot,
      hour: slot.getHours(),
      meters: Number(hours[String(slot.getHours())]) || 0,
      isCurrent: offset === 0
    })
  }
  return out
}

function seriesValues(series) {
  var out = []
  for (var i = 0; i < series.length; i++) out.push(series[i].meters)
  return out
}

// "↓12%" reads as progress at a glance where "-12%" reads as a loss.
function deltaArrow(value, baseline) {
  if (!baseline || baseline <= 0) return ""
  var percent = Math.round((value / baseline - 1) * 100)
  if (percent === 0) return "="
  return (percent < 0 ? "↓" : "↑") + Math.abs(percent) + "%"
}

function hourLabel(date) {
  return Qt.formatDateTime(date, "HH:00")
}

// Today's 24 calendar hours, so the panel's chart has a fixed axis you can
// compare one day against the next with.
function todayHourly(state, reference) {
  var now = reference || new Date()
  var day = bucket(state, dayKey(now))
  var hours = day.hours || {}
  var out = []
  for (var hour = 0; hour < 24; hour++) {
    out.push({
      hour: hour,
      label: (hour < 10 ? "0" : "") + hour + ":00",
      meters: Number(hours[String(hour)]) || 0,
      isCurrent: hour === now.getHours(),
      future: hour > now.getHours()
    })
  }
  return out
}
