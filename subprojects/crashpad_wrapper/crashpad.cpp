#include "client/crashpad_client.h"
#include "client/crash_report_database.h"
#include "client/settings.h"

#include <string.h>

extern "C" {
  bool initialised = false;

  #define MIN(x, y) (((x) < (y)) ? (x) : (y))

  using namespace base;
  using namespace crashpad;
  using namespace std;

  unique_ptr<CrashReportDatabase> database = NULL;

  string getExecutableDir() {
	char pBuf[FILENAME_MAX];
	int len = sizeof(pBuf);
	int bytes = MIN(readlink("/proc/self/exe", pBuf, len), len - 1);
	if (bytes >= 0) {
		pBuf[bytes] = '\0';
	}

	char* lastForwardSlash = strrchr(&pBuf[0], '/');
	if (lastForwardSlash == NULL) return NULL;
	*lastForwardSlash = '\0';

	return pBuf;
  }

  void crashpad_init(const char *dump_path, const char *product_name, const char *product_version, const char *url, const char *user_id) {
    if (initialised) {
      return;
    }

    // Get directory where the exe lives so we can pass a full path to handler, reportsDir and metricsDir
    string exeDir = getExecutableDir();

    // Ensure that crashpad_handler is shipped with your application
    FilePath handler(exeDir + "/pakiki_crashpad_handler");

    // Directory where reports will be saved. Important! Must be writable or crashpad_handler will crash.
    FilePath reportsDir(dump_path);

    // Directory where metrics will be saved. Important! Must be writable or crashpad_handler will crash.
    FilePath metricsDir(dump_path);

    // Metadata that will be posted to BugSplat
    map<string, string> annotations;
    annotations["product"] = product_name;
    annotations["release"] = product_version;
    annotations["user"] = user_id;
    
    // Disable crashpad rate limiting so that all crashes have dmp files
	vector<string> arguments; 
	arguments.push_back("--no-rate-limit");

	// File paths of attachments to be uploaded with the minidump file at crash time - default bundle limit is 20MB
	vector<FilePath> attachments;
	/*FilePath attachment(exeDir + "/attachment.txt");
	attachments.push_back(attachment);  */

	// Initialize Crashpad database
	database = CrashReportDatabase::Initialize(reportsDir);
	if (database == NULL) return;

    if (strcmp(url, "") == 0) {
      return;
    }

	// Enable automated crash uploads
	Settings *settings = database->GetSettings();
	if (settings == NULL) return;
	settings->SetUploadsEnabled(true);

    // Start crash handler
    CrashpadClient *client = new CrashpadClient();
    initialised = client->StartHandler(handler, reportsDir, metricsDir, url, annotations, arguments, true, true, attachments);
  }

  void crashpad_set_automatic_reporting(const char report_path, bool automatic_reporting) {
    // Initialize Crashpad database
	if (database == NULL) return;

	// Enable automated crash uploads
	Settings *settings = database->GetSettings();
	if (settings == NULL) return;
	settings->SetUploadsEnabled(automatic_reporting);
  }
}
