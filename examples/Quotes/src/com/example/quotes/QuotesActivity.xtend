package com.example.quotes

import java.util.Random
import android.view.View
import org.xtendroid.app.AndroidActivity
import android.app.Activity
import android.os.Bundle
import android.databinding.DataBindingUtil
import org.eclipse.xtend.lib.annotations.Accessors
import org.xtendroid.content.res.AndroidResources

// xtend can't find my generated MainActivityBinding
import com.example.quotes.databinding.MainActivityBinding

@Accessors
class Quote
{
    String quote
}

@AndroidActivity(layout=R.layout.main_activity) class QuotesActivity extends Activity {

    val quote = new Quote

    val rng = new Random()

    // broken because R.string doesn't even exist yet
    @AndroidResources(type=R.string, path='res/values/strings.xml')
    var Strings strings

    override onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState)
        // xtend can't find my generated MainActivityBinding
        var binding = DataBindingUtil.setContentView(this, R.layout.main_activity) as MainActivityBinding

        // Use auto-generated class
        //binding.quote = quote
    }

    override void nextQuote(View v) {
        // update model
        val i = rng.nextInt(strings.quotes.length)
        quote.quote = strings.quotes.get(i)
        // quoteView.text = strings.quotes.get(i) // android data binding is a roundabout way to do this
    }

}
