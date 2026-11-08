package app.mobilebasic;

import android.os.Bundle;
import android.widget.TextView;
import androidx.appcompat.app.AppCompatActivity;

/**
 * Minimal entry point for the mobilebasic scaffold.
 *
 * The app deliberately has no network, no analytics and no third-party SDKs:
 * it exists so the toolchain (aapt2 / d8 / apksigner / adb) and the
 * mobile-debug MCP have something real to build, install and inspect.
 */
public class MainActivity extends AppCompatActivity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        TextView status = new TextView(this);
        status.setText("mobilebasic");
        status.setTextSize(20f);
        status.setPadding(48, 48, 48, 48);
        setContentView(status);
    }
}
