package org.xtendroid.xtendroidtest.test

import android.test.ActivityInstrumentationTestCase2
import android.widget.TextView
import org.xtendroid.xtendroidtest.MainActivity
import org.xtendroid.xtendroidtest.R

class ActivityAnnotation extends ActivityInstrumentationTestCase2<MainActivity> {
	
	new() {
		super(MainActivity)
	}
	
	def void testAnnotation() {
		val annotationTv = (activity as MainActivity).mainHello
		val tv = activity.findViewById(R.id.main_hello) as TextView
		assertEquals(activity.getString(R.string.hello_world), tv.text)
		
		activity.runOnUiThread [|
			annotationTv.text = "Testing"
			assertEquals(annotationTv.text, tv.text)
		]
		
		Thread.sleep(1000) // wait for above thread to run
	}
}