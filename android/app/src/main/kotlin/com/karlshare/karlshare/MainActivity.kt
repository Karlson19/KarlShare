package com.karlshare.karlshare

import android.content.Context
import com.karlshare.karlshare.apps.InstalledAppsService
import com.karlshare.karlshare.discovery.DiscoveryService
import com.karlshare.karlshare.transfer.TransferEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import java.util.UUID

class MainActivity : FlutterActivity() {

    private var discovery: DiscoveryService? = null
    private var transfer: TransferEngine? = null
    private var apps: InstalledAppsService? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger
        discovery = DiscoveryService(applicationContext, messenger)
        transfer = TransferEngine(applicationContext, messenger, deviceId(applicationContext))
        apps = InstalledAppsService(applicationContext, messenger)
    }

    override fun onDestroy() {
        discovery?.dispose(); discovery = null
        transfer?.dispose(); transfer = null
        apps?.dispose(); apps = null
        super.onDestroy()
    }

    /**
     * Stable per-install UUID — persists across launches so the same physical
     * device shows up as the same peer in another device's history. Generated
     * on first launch and stashed in SharedPreferences.
     */
    private fun deviceId(context: Context): UUID {
        val prefs = context.getSharedPreferences("karlshare_native", Context.MODE_PRIVATE)
        val existing = prefs.getString("device_id", null)
        if (existing != null) {
            return runCatching { UUID.fromString(existing) }.getOrElse { UUID.randomUUID() }
        }
        val fresh = UUID.randomUUID()
        prefs.edit().putString("device_id", fresh.toString()).apply()
        return fresh
    }
}
