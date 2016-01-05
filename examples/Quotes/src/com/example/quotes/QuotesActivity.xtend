package com.example.quotes

import android.content.Context
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import org.xtendroid.app.AndroidActivity
import android.app.Activity
import android.os.Bundle
import android.widget.Toast
import android.view.Gravity
import android.databinding.DataBindingUtil
import org.eclipse.xtend.lib.annotations.Accessors
import org.xtendroid.content.res.AndroidResources

@Accessors
class Quote
{
   String quote
   String by
}

@AndroidActivity(R.layout.main) class QuotesActivity extends Activity {

   val quote = new Quote

   @AndroidResources(type=R.string)
   var Strings strings

   override onCreate(Bundle savedInstanceState) {
      super.onCreate(savedInstanceState)
      var binding = DataBindingUtil.setContentView(this, R.layout.main)
      quote.by = "Buggaboo"
      quote.quote = "duhh..."

      // Use auto-generated class
      /*
      var b = binding as QuotesActivityBinding
      b.quote = quote;
      */
}
   
   /**
    * Type safe callback
    */
   override void nextQuote(View v) {
      // update model
      quote.by = strings.quotes.get(0)
      quote.quote = strings.quotes.get(0)
   }
   
}
