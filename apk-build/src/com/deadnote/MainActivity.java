package com.deadnote;

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;
import android.widget.ImageView;


public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        ImageView fondo = new ImageView(this);
        fondo.setImageResource(R.drawable.fondo_app);
        fondo.setScaleType(ImageView.ScaleType.CENTER_CROP);
        
        setContentView(fondo);
 
        // setContentView(R.layout.activity_main);
        TextView textView = new TextView(this);
        textView.setText(R.string.text_hello_world);
        textView.setTextSize(22);
        setContentView(textView);
    }
}

