package com.ciabosoftwaresolutions.liveactivities

import org.json.JSONObject

internal data class DisplayAction(val id: String, val label: String, val url: String, val icon: String = "open", val emphasis: String = "secondary")
internal data class DisplayProjection(
    val template: String,
    val icon: String,
    val status: String,
    val url: String,
    val indicator: String,
    val timer: JSONObject?,
    val showSubtitle: Boolean,
    val lines: List<String>,
    val actions: List<DisplayAction>,
    val phase: String,
    val header: String,
)

internal object DisplayContract {
    fun project(display: JSONObject?): DisplayProjection? {
        if (display == null || display.optInt("version") != 2 ||
            display.optString("template") !in listOf("summary", "progress")) return null
        val profiles = display.optJSONObject("profiles") ?: return null
        val expanded = profiles.optJSONObject("expanded") ?: return null
        val items = display.optJSONArray("items") ?: return null
        val actions = display.optJSONArray("actions") ?: return null
        val itemIds = expanded.optJSONArray("itemIds") ?: return null
        val actionIds = expanded.optJSONArray("actionIds") ?: return null
        val selectedLines = (0 until minOf(itemIds.length(), 3)).mapNotNull { index ->
            val id = itemIds.optString(index)
            val item = (0 until items.length()).mapNotNull { items.optJSONObject(it) }
                .firstOrNull { it.optString("id") == id } ?: return@mapNotNull null
            listOf(item.optString("badge"), item.optString("label"), item.optString("value"),
                "Selected".takeIf { item.optBoolean("selected", false) } ?: "")
                .filter { it.isNotBlank() && it != "null" }.joinToString(" ")
        }
        val selectedActions = (0 until minOf(actionIds.length(), 2)).mapNotNull { index ->
            val id = actionIds.optString(index)
            val action = (0 until actions.length()).mapNotNull { actions.optJSONObject(it) }
                .firstOrNull { it.optString("id") == id } ?: return@mapNotNull null
            DisplayAction(id, action.optString("label"), action.optString("url"),
                action.optString("icon", "open"), action.optString("emphasis", "secondary"))
        }
        return DisplayProjection(
            display.optString("template"), display.optString("icon", "info"),
            display.optString("status"), display.optString("url"),
            profiles.optJSONObject("compact")?.optString("indicator", "icon") ?: "icon",
            display.optJSONObject("timer"), expanded.optBoolean("showSubtitle", true),
            selectedLines, selectedActions, display.optString("phase"), display.optString("header"),
        )
    }
}