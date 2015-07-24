package org.xtendroid.xtendroidtest.activities

import android.app.ProgressDialog
import android.widget.BaseAdapter
import java.util.Date
import java.util.List
import org.xtendroid.adapter.BeanAdapter
import org.xtendroid.app.AndroidActivity
import org.xtendroid.app.OnCreate
import org.xtendroid.xtendroidtest.R
import org.xtendroid.xtendroidtest.models.ManyItem

import static org.xtendroid.utils.AsyncBuilder.*

import static extension org.xtendroid.utils.AlertUtils.*
import static extension org.xtendroid.xtendroidtest.db.DbService.*

@AndroidActivity(R.layout.list_and_text) class DbTestActivity {
	var List<ManyItem> manyItems 
	
	@OnCreate
	def init() {
		manyItems = db.lazyFindAll("manyitems", "id", ManyItem)
		mainList.adapter = new BeanAdapter(this, R.layout.main_list_row, manyItems)
		
		if (manyItems.size == 0) {
			// let's make many items
			val pd = new ProgressDialog(this)
			pd.setProgressStyle(ProgressDialog.STYLE_HORIZONTAL)
			pd.title = "Creating many items"
			pd.indeterminate = false
			pd.max = 1000
			pd.progress = 0
			val now = new Date
			
			async(pd) [a, params|
				(0..1000).forEach [i|
					db.insert("manyitems", #{
						'createdAt' -> now,
						'itemName' -> "Item " + i,
						'itemOrder' -> i
					})

               if (a.isCancelled) return;
					a.progress(i)
				]
				"done"
			].then [String r|
				manyItems = db.lazyFindAll("manyitems", "id", ManyItem)
				(mainList.adapter as BaseAdapter).notifyDataSetChanged
			].onProgress[Object[] values|
			   pd.progress = values.get(0) as Integer
			].onError [Exception e|
				toast("ERROR: " + e.message)
			].start()
		}
	}
}