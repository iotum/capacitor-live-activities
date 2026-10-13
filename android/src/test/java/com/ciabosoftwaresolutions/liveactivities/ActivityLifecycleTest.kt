package com.ciabosoftwaresolutions.liveactivities

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.Callable
import java.util.concurrent.Executors

class ActivityLifecycleTest {
    private var stored: String? = null
    private var currentTime = 1_900_000_000L
    private val shown = mutableListOf<Pair<String, Boolean>>()
    private val cancelled = mutableListOf<String>()
    private val state = JSONObject().put("title", "In call")

    private fun lifecycle() = ActivityLifecycle(
        load = { stored },
        save = { stored = it },
        show = { info, _, ongoing -> shown.add(info.activityId to ongoing) },
        cancel = { info -> cancelled.add(info.activityId) },
        now = { currentTime },
    )

    @Test fun finishBeforeStartSurvivesRestartAndRejectsSameSecondPushes() {
        assertEquals("applied", lifecycle().apply("end", "call:1", state, currentTime, false).status)
        val restarted = lifecycle()
        assertEquals("ignored", restarted.apply("update", "call:1", state, currentTime, true).status)
        assertEquals("ignored", restarted.apply("start", "call:1", state, currentTime, true).status)
        assertTrue(shown.isEmpty())
        assertTrue(restarted.activeActivities().isEmpty())
    }

    @Test fun restoresActiveIdentityAndEndsItAfterRestart() {
        val activityId = lifecycle().apply("start", "call:1", state, currentTime, true).activityId
        val restarted = lifecycle()
        restarted.reconcile(setOf(activityId!!))
        assertEquals(activityId, restarted.activeActivities().single().activityId)
        assertEquals(activityId, restarted.apply("update", "call:1", state, currentTime, true).activityId)
        restarted.apply("end", "call:1", null, currentTime, false)
        assertEquals(listOf(activityId), cancelled)
        assertEquals("ignored", lifecycle().apply("update", "call:1", state, currentTime + 1, true).status)
    }

    @Test fun allowsSameSecondUpdatesButRejectsStrictlyOlderUpdates() {
        val manager = lifecycle()
        manager.apply("start", "call:1", state, currentTime, true)
        assertEquals("applied", manager.apply("update", "call:1", state, currentTime, true).status)
        assertEquals("ignored", manager.apply("update", "call:1", state, currentTime - 1, true).status)
        assertEquals(2, shown.size)
    }

    @Test fun permissionRetryCannotUndoAnEnd() {
        val manager = lifecycle()
        assertEquals("permission-required", manager.apply("start", "call:1", state, currentTime, false).status)
        manager.apply("end", "call:1", state, currentTime, false)
        assertEquals("ignored", manager.apply("start", "call:1", state, currentTime, true).status)
        assertTrue(shown.isEmpty())
    }

    @Test fun reconciliationDoesNotRecreateMissingNotifications() {
        lifecycle().apply("start", "call:1", state, currentTime, true)
        val restarted = lifecycle()
        restarted.reconcile(emptySet())
        assertTrue(restarted.activeActivities().isEmpty())
        assertEquals("ignored", lifecycle().apply("update", "call:1", state, currentTime, true).status)
    }

    @Test fun pruningFinishedKeysStillRejectsExpiredPushes() {
        lifecycle().apply("end", "call:1", state, currentTime, false)
        val originalTime = currentTime
        currentTime += ActivityLifecycle.RETENTION_SECONDS + 1
        val restarted = lifecycle()
        assertEquals("ignored", restarted.apply("update", "call:1", state, originalTime, true).status)
        assertFalse(JSONObject(stored!!).has("call:1"))
        assertEquals("applied", restarted.apply("start", "call:2", state, currentTime, true).status)
    }

    @Test fun failedPersistenceDoesNotShowANotification() {
        val manager = ActivityLifecycle(
            load = { null },
            save = { throw IllegalStateException("Disk full") },
            show = { info, _, ongoing -> shown.add(info.activityId to ongoing) },
            cancel = {},
            now = { currentTime },
        )
        try {
            manager.apply("start", "call:1", state, currentTime, true)
            fail("Expected persistence failure")
        } catch (_: IllegalStateException) {
            assertTrue(manager.activeActivities().isEmpty())
            assertTrue(shown.isEmpty())
        }
    }

    @Test fun concurrentUpdatesCannotShowOngoingStateAfterFinish() {
        val manager = lifecycle()
        manager.apply("start", "call:1", state, currentTime, true)
        val executor = Executors.newFixedThreadPool(4)
        try {
            val events = List(8) { "update" } + "end" + List(8) { "update" }
            executor.invokeAll(events.map { event ->
                Callable { manager.apply(event, "call:1", state, currentTime, true) }
            }).forEach { it.get() }
        } finally {
            executor.shutdownNow()
        }
        assertFalse(shown.last().second)
        assertEquals(1, shown.count { !it.second })
        assertTrue(manager.activeActivities().isEmpty())
        assertEquals("ignored", lifecycle().apply("start", "call:1", state, currentTime, true).status)
    }
}