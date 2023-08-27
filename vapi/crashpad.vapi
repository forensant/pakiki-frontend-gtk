
//[CCode (cheader_filename = "subprojects/crashpad_wrapper/crashpad.h")]
[CCode]
namespace Crashpad {
  [CCode (cname = "crashpad_init")]
  public static void setup (string dump_path, string product_name, string product_version, string url, string user_id);

  [CCode (cname = "crashpad_set_automatic_reporting")]
  void set_automatic_reporting (string report_path, bool automatic_reporting);

  public static int init ();
}