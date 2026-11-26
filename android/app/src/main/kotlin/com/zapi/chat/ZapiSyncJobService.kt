package com.zapi.chat

import android.app.job.JobParameters
import android.app.job.JobService
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore

class ZapiSyncJobService : JobService() {

    override fun onStartJob(params: JobParameters?): Boolean {
        if (FirebaseApp.getApps(this).isEmpty()) {
            FirebaseApp.initializeApp(this)
        }

        if (!ZapiMessageNotifier.isBackgroundEnabled(this) || ZapiMessageService.isRunning) {
            jobFinished(params, false)
            return false
        }

        val uid = try {
            FirebaseAuth.getInstance().currentUser?.uid
        } catch (_: Exception) {
            null
        }

        if (uid.isNullOrEmpty()) {
            jobFinished(params, false)
            return false
        }

        FirebaseFirestore.getInstance()
            .collection("chats")
            .whereArrayContains("participants", uid)
            .get()
            .addOnSuccessListener { snapshot ->
                ZapiMessageNotifier.handleFetchedDocs(
                    context = applicationContext,
                    currentUid = uid,
                    docs = snapshot.documents
                )
                jobFinished(params, false)
            }
            .addOnFailureListener {
                jobFinished(params, true)
            }

        return true
    }

    override fun onStopJob(params: JobParameters?): Boolean {
        return true
    }
}
