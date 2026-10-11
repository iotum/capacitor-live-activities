package com.ciabosoftwaresolutions.liveactivities

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class DisplayContractTest {
    private fun fixture(): JSONObject = JSONObject(File("../docs/fixtures/call.json").readText())

    @Test fun preservesRailsSelectionOrder() {
        val display = fixture().getJSONObject("display")
        display.getJSONObject("profiles").getJSONObject("expanded")
            .put("itemIds", org.json.JSONArray(listOf("tier", "tickets")))
        val projection = DisplayContract.project(display)!!
        assertEquals(listOf("Account Gold", "Open tickets 3"), projection.lines)
        assertEquals("record", projection.actions.first().id)
        assertEquals("elapsed", projection.timer!!.getString("mode"))
    }

    @Test fun fallsBackForUnknownVersion() {
        assertNull(DisplayContract.project(fixture().getJSONObject("display").put("version", 99)))
    }

    @Test fun preservesStylingTokensAndSelectedBadges() {
        val display = fixture().getJSONObject("display")
        display.getJSONArray("items").getJSONObject(0).put("selected", true)
        val projection = DisplayContract.project(display)!!
        assertEquals("connected", projection.phase)
        assertEquals("HubSpot", projection.header)
        assertEquals("record", projection.actions.first().icon)
        assertEquals("primary", projection.actions.first().emphasis)
        assertEquals("Open tickets 3 Selected", projection.lines.first())
    }

    @Test fun preservesFrozenTimerAndEmptySelections() {
        val display = fixture().getJSONObject("display")
        display.put("timer", JSONObject("""{"mode":"frozen","seconds":125}"""))
        display.getJSONObject("profiles").getJSONObject("expanded").put("itemIds", org.json.JSONArray())
        val projection = DisplayContract.project(display)!!
        assertTrue(projection.lines.isEmpty())
        assertEquals(125, projection.timer!!.getInt("seconds"))
    }
}