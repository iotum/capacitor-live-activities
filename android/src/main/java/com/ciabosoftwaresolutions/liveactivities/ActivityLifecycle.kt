package com.ciabosoftwaresolutions.liveactivities

import org.json.JSONObject
import java.util.UUID

data class ActivityInfo(
    val activityId: String,
    val activityType: String,
    val state: String,
    val notificationId: Int,
)

data class ActivityEventResult(val status: String, val activityId: String? = null)

class ActivityLifecycle(
    load: () -> String?,
    private val save: (String) -> Unit,
    private val show: (ActivityInfo, JSONObject, Boolean) -> Unit,
    private val cancel: (ActivityInfo) -> Unit,
    private val now: () -> Long = { System.currentTimeMillis() / 1000 },
) {
    companion object {
        const val RETENTION_SECONDS = 24 * 60 * 60L
    }

    private data class Entry(val info: ActivityInfo, val timestamp: Long, val finishedAt: Long? = null)

    private val entries = linkedMapOf<String, Entry>()

    init {
        val stored = JSONObject(load() ?: "{}")
        stored.keys().forEach { key ->
            val entry = stored.getJSONObject(key)
            val finishedAt = if (entry.has("finishedAt")) entry.getLong("finishedAt") else null
            entries[key] = Entry(
                ActivityInfo(entry.getString("activityId"), key, if (finishedAt == null) "active" else "ended", entry.getInt("notificationId")),
                entry.getLong("timestamp"),
                finishedAt,
            )
        }
    }

    @Synchronized
    fun apply(event: String, key: String, state: JSONObject?, timestamp: Long, canStart: Boolean): ActivityEventResult {
        require(event in listOf("start", "update", "end")) { "Unknown Live Activity event" }
        require(key.isNotBlank()) { "Live Activity key must not be blank" }
        require(timestamp > 0) { "Live Activity timestamp must be positive" }
        require(event == "end" || state != null) { "Live Activity state is required" }
        val currentTime = now()
        prune(currentTime)
        if (timestamp < currentTime - RETENTION_SECONDS) return ActivityEventResult("ignored")

        val previous = entries[key]
        if (previous?.finishedAt != null) return ActivityEventResult("ignored")
        if (event != "end" && previous != null && timestamp < previous.timestamp) return ActivityEventResult("ignored")
        if (event != "end" && previous == null && !canStart) return ActivityEventResult("permission-required")

        val activityId = previous?.info?.activityId ?: UUID.randomUUID().toString()
        val info = ActivityInfo(activityId, key, if (event == "end") "ended" else "active", activityId.hashCode())
        val entry = Entry(info, timestamp, if (event == "end") currentTime else null)
        val updated = entries.toMutableMap().apply { put(key, entry) }
        persist(updated)
        entries[key] = entry

        if (event == "end") {
            if (previous != null) {
                if (state != null) show(info, state, false) else cancel(info)
            }
        } else {
            show(info, state!!, true)
        }
        return ActivityEventResult("applied", activityId)
    }

    @Synchronized
    fun activeActivities(): List<ActivityInfo> = entries.values.filter { it.finishedAt == null }.map { it.info }

    @Synchronized
    fun reconcile(notificationActivityIds: Set<String>) {
        val currentTime = now()
        val updated = entries.mapValues { (_, entry) ->
            if (entry.finishedAt == null && entry.info.activityId !in notificationActivityIds) {
                entry.copy(info = entry.info.copy(state = "ended"), finishedAt = currentTime)
            } else entry
        }.filterValues { it.finishedAt == null || it.finishedAt >= currentTime - RETENTION_SECONDS }
        persist(updated)
        entries.clear()
        entries.putAll(updated)
    }

    private fun prune(currentTime: Long) {
        val updated = entries.filterValues { it.finishedAt == null || it.finishedAt >= currentTime - RETENTION_SECONDS }
        if (updated.size != entries.size) {
            persist(updated)
            entries.clear()
            entries.putAll(updated)
        }
    }

    private fun persist(updated: Map<String, Entry>) {
        val stored = JSONObject()
        updated.forEach { (key, entry) ->
            val value = JSONObject()
                .put("activityId", entry.info.activityId)
                .put("notificationId", entry.info.notificationId)
                .put("timestamp", entry.timestamp)
            entry.finishedAt?.let { value.put("finishedAt", it) }
            stored.put(key, value)
        }
        save(stored.toString())
    }
}