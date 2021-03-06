    Author: Andreas Linde <mail@andreaslinde.de>

    Copyright (c) 2009-2014 Andreas Linde.
    All rights reserved.

    Permission is hereby granted, free of charge, to any person
    obtaining a copy of this software and associated documentation
    files (the "Software"), to deal in the Software without
    restriction, including without limitation the rights to use,
    copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the
    Software is furnished to do so, subject to the following
    conditions:

    The above copyright notice and this permission notice shall be
    included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
    EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
    OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
    NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
    HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
    WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
    OTHER DEALINGS IN THE SOFTWARE.


# Main features of QuincyKit

- (Automatically) send crash reports to a developers database
- Let the user decide per crash to (not) send data or always send
- The user has the option to provide additional information in the settings, like email address for contacting the user
- Give the user immediate feedback if the crash is known and will be fixed in the next update, or if the update is already waiting at Apple for approval, or if the update is already available to install


# Main features on backend side for the developer

- Admin interface to manage the incoming crash log data
- Script to symbolicate crash logs on the database, needs to be run on a mac with access to the DSYM files
- Automatic grouping of crash files for most likely same kind of crashes
- Maintain crash reports and sort them by using simple patterns. Automatically know how many times a bug has occured and easily filter the new ones in the DB
- Assign bugfix versions for each crash group and define a status for each version, which can be used to provide some feedback for the user
  like: Bug already fixed, new version with bugfix already available, etc.


## Server side files

- `/server/database_schema.sql` contains all the default tables
- `/server/crash_v300.php` is the file that is invoked by the iPhone app
- `/server/config.php` contains database access information
- `/server/test_setup.php` simple script that checks if everything required on the server is available
- `/server/admin/` contains all administration scripts


# SERVER INSTALLATION

The server requires at least PHP 5.2 and a MySQL server installation!

- Copy the server scripts to your web server:
  All files inside /server except the content of the `/server/local` directory
- Execute the SQL statements from `database_schema.sql` in your MySQL database on the web server


## SERVER DATABASE CONFIGURATION

- Adjust settings in `/server/config.php`:

    $server = 'your.server.com';            // database server hostname
    $loginsql = 'database_username';        // username to access the database
    $passsql = 'database_password';         // password for the above username
    $base = 'database_name';                // database name which contains the below listed tables

- Adjust `$default_amount_crashes`, this defines the amount of crashes listed right away per pattern, if there are more, those are shown after clicking on a link at the end of the shortened list
- Adjust your local timezone in the last line: `date_default_timezone_set('Europe/Berlin')` (see [http://php.net/manual/en/timezones.php](http://php.net/manual/en/timezones.php "PHP: List of Supported Timezones - Manual"))
- If you DO NOT want to limit the server to accept only data for your applications:
  - set `$acceptallapps` to true
- Otherwise:
  - start the web interface
  - add the bundle identifiers of the permitted apps, e.g. `"de.buzzworks.crashreporterdemo"` (this is the same bundle identifier string as used in the `info.plist` of your app!)
- Invoke `test_setup.php` via the browser to check if everything is setup correctly and Push can be used or not

- If you are upgrading a previous edition, invoke 'migrate.php' first to update the database setup


## UPDATE SERVER TO QUINCYKIT 3.0

Database schema and clients changed. Therefor it is recommended to setup a new installation!


## SERVER ENABLE PUSH NOTIFICATIONS

- **NOTICE**: Push Notification requires the Server PHP installation to have curl addon installed!
- **NOTICE**: Push Notifications are implemented using Prowl iPhone app and web service, you need the app and an Prowl API key!
- Adjust settings in `/server/config.php`:
    - set `$push_activated` to true
    - if you don't want a push message for every new pattern, set `$push_newtype` to false
    - adjust `$notify_amount_group` to the amount of crash occurences of a pattern when a push message should be sent
    - add up to 5 comma separated prowl api keys into $push_prowlids to receive the push messages on the device
    - adjust `$notify_default_version`, defines if you want to receive pushes for automatically created new versions for your apps
- If push is activated, check the web interface for push settings per app version


# SETUP LOCAL SYMBOLIFICATION

- **NOTICE**: These are the instructions when using Mac OS X 10.6.2
- Copy the files inside of `/server/local` onto a local directory on your Intel Mac running at least Mac OS X 10.6.2 having the iPhone SDK 3.x installed
- Adjust settings in `local/serverconfig.php`
  - set `$hostname` to the server hostname running the server side part, e.g. `www.crashreporterdemo.com`
  - if the `/admin/` directory on the server is access restricted, set the required username into `$webuser` and password into `$webpwd`
  - adjust the path to access the scripts (will be appended to `$hostname`):
      - `$downloadtodosurl = '/admin/actionapi.php?action=getsymbolicationtodo';`	// the path to the script delivering the todo list
      - `$getcrashdataurl = '/admin/actionapi.php?action=getlogcrashid&id=';`		// the path to the script delivering the crashlog
      - `$updatecrashdataurl = '/admin/crash_update.php';`						// the path to the script updating the crashlog
- Make the modified symbolicatecrash.pl file from the `/server/local/` directory executable: `chmod + x symbolicatecrash.pl`
- Copy the `.app` package and `.app.dSYM` package of each version into any directory of your Mac
  Best is to add the version number to the directory of each version, so multiple versions of the same app can be symbolicated.
  Example:
  
        QuincyDemo_1_0/QuincyDemo.app
        QuincyDemo_1_0/QuincyDemo.app.dSYM
        QuincyDemoBeta_1_1/QuincyDemoBeta.app
        QuincyDemoBeta_1_1/QuincyDemoBeta.app.dSYM
      
- Test symbolification:
  - Download a crash report into the local directory from above
  - run `symbolicatecrash nameofthecrashlogfile .`
  - if the output shows function names and line numbers for your code and apples code, everything is fine and ready to go, otherwise there is a problem :(
- If test was successful, try to execute `php symbolicate.php`
  This will print some error message which can be ignored
- Open the web interface and check the crashlogs if they are now symbolicated
- If everything went fine, setup a cron job
- IMPORTANT: Don't forget to add new builds with `.app` and `.app.dSYM` packages to the directory, so symbolification will be done correctly
  There is currently no checking if a package is found in the directory before symbolification is started, no matter if it was or not, the result will be uploaded to the server
  

# iOS Setup

For QuincyKit 3.0:

- Include `BWQuincyManager.h`, `BWQuincyManager.m`, `BWQuincyManagerDelegate.h`, `BWCrashReportTextFormatter.h`, `BWCrashReportTextFormatter.m`, and `Quincy.bundle` into your project
- Include `CrashReporter.framework` into your project
- Add the Apple framework `SystemConfiguration.framework` to your project
- In your `appDelegate.m` include

      #import "BWQuincyManager.h"

- In your appDelegate `applicationDidFinishLaunching:` implementation include

      [[BWQuincyManager sharedQuincyManager] setSubmissionURL:@"http://yourserver.com/crash_v300.php"];
      [[BWQuincyManager sharedQuincyManager] startManager];
      
- If you want to implement any of the delegates, add the following before the `startManager` call:

      [[BWQuincyManager sharedQuincyManager] setDelegate:self];
  
  and set the protocol to your appDelegate:
  
      @interface YourAppDelegate : NSObject <BWQuincyManagerDelegate> {}
      
- Done.


# MAC Setup

- Open the `Quincy.xcodeproj` in the folder `client/Mac/`
- Build the `Quincy.framework`
- Include `Quincy.framework` into your project
- In your `appDelegate.m` include

      #import <Quincy/BWQuincyManager.h>

- In your `appDelegate` change the invocation of the main window to the following structure

      - (void)applicationDidFinishLaunching:(NSNotification *)note
      {
        // Launch the crash reporter task
        [[BWQuincyManager sharedQuincyManager] setSubmissionURL:@"http://yourserver.com/crash_v200.php"];
        [[BWQuincyManager sharedQuincyManager] setDelegate:self];
      }
     
- If you want to implement any of the delegates, add the following before the `startManager` call:

      [[BWQuincyManager sharedQuincyManager] setDelegate:self];
  
  and set the protocol to your appDelegate:
  
      @interface YourAppDelegate : NSObject <BWQuincyManagerDelegate> {}

- If you want to catch additional exceptions which the Mac runtime usually does not forward, open the `Info.plist` and set `Principal class` to `BWQuincyCrashExceptionApplication`. Check the header file of that class for further documentation.

- Done.


# BRANCHES:
The branching structure follows the git flow concept, defined by Vincent Driessen: http://nvie.com/posts/a-successful-git-branching-model/

* Master branch:

	The main branch where the source code of HEAD always reflects a production-ready state.

* Develop branch:

	Consider this to be the main branch where the source code of HEAD always reflects a state with the latest delivered development changes for the next release. Some would call this the “integration branch”.

* Feature branches:

	These are used to develop new features for the upcoming or a distant future release. The essence of a feature branch is that it exists as long as the feature is in development, but will eventually be merged back into develop (to definitely add the new feature to the upcoming release) or discarded (in case of a disappointing experiment).

* Release branches:

	These branches support preparation of a new production release. By using this, the develop branch is cleared to receive features for the next big release.

* Hotfix branches:

	Hotfix branches are very much like release branches in that they are also meant to prepare for a new production release, albeit unplanned.


# Dependencies

## Server

Web server supporting PHP 5.0+ and MySQL.

## Mac OS X

Requires Max OS X 10.5+

## iOS

Requires iOS 6.0+ (iOS 4.3 as lowest deployment target)
Supports armv7, armv7s, arm64

## iOS Support for non ARC projects

If you are including QuincyKit in an iOS project without Automatic Reference Counting (ARC) enabled, you will need to set the `-fobjc-arc` compiler flag on all of the QuincyKit source files. To do this in Xcode, go to your active target and select the "Build Phases" tab. In the "Compiler Flags" column, set `-fobjc-arc` for each of the QuincyKit source files.


# ACKNOWLEDGMENTS

**The following 3rd party open source libraries have been used:**

- PLCrashReporter by Landon Fuller (http://plcrashreporter.org/)
- bluescreen css framework (http://blueprintcss.org/)


Feel free to add enhancements, fixes, changes and provide them back to the community!

Thanks  
Andreas Linde  
http://www.andreaslinde.com/
http://www.hockeyapp.net/
