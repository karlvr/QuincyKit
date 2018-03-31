<?php

	/*
	 * Author: Andreas Linde <mail@andreaslinde.de>
	 *
	 * Copyright (c) 2009-2014 Andreas Linde & Kent Sutherland.
	 * All rights reserved.
	 *
	 * Permission is hereby granted, free of charge, to any person
	 * obtaining a copy of this software and associated documentation
	 * files (the "Software"), to deal in the Software without
	 * restriction, including without limitation the rights to use,
	 * copy, modify, merge, publish, distribute, sublicense, and/or sell
	 * copies of the Software, and to permit persons to whom the
	 * Software is furnished to do so, subject to the following
	 * conditions:
	 *
	 * The above copyright notice and this permission notice shall be
	 * included in all copies or substantial portions of the Software.
	 *
	 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
	 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
	 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
	 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
	 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
	 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
	 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
	 * OTHER DEALINGS IN THE SOFTWARE.
	 */

//
// Shows a list of crashes for a given crash group
//
// Shows all crashes for a given crash group. You can download each crash
// from this view, or see all the relevant information about this crash
// that is available
//

require_once('../config.php');
require_once('common.inc');

init_database();
parse_parameters(',groupid,bundleidentifier,version,search,type,');

if (!isset($all)) $all = false;
if (!isset($groupid)) $groupid = "";
if (!isset($bundleidentifier)) $bundleidentifier = "";
if (!isset($version)) $version = "";
if (!isset($search)) $search = "";
if (!isset($type)) $type = "";

if ($bundleidentifier == "" && ($version == "" || $type = "")) die(end_with_result('Wrong parameters'));

$whereclause = "";
$pagelink = "";

if ($search != "" && $type != "") {
	$pagelink = '?bundleidentifier='.$bundleidentifier.'&search='.$search.'&type='.$type;
    if ($version != "") {
        $pagelink .= "&version=".$version;
    }
	$whereclause = " WHERE bundleidentifier = '".$bundleidentifier."'";
	if ($type == SEARCH_TYPE_ID)
        $whereclause .= " AND id = '".$search."'";
    else if ($type == SEARCH_TYPE_DESCRIPTION)
        $whereclause .= " AND description like '%".$search."%'";
    else if ($type  == SEARCH_TYPE_CRASHLOG)
        $whereclause .= " AND log like '%".$search."%'";
    else if ($type  == SEARCH_TYPE_CONTACT)
        $whereclause .= " AND contact like '%".$search."%'";
    else if ($type  == SEARCH_TYPE_USERID)
        $whereclause .= " AND userid like '%".$search."%'";
    else if ($type  == SEARCH_TYPE_USERNAME)
        $whereclause .= " AND username like '%".$search."%'";
    if ($version != "")
    	$whereclause .= " AND version = '".$version."'";
} else if ($groupid == "") {
	$pagelink = '?bundleidentifier='.$bundleidentifier.'&version='.$version;
	$whereclause = " WHERE bundleidentifier = '".$bundleidentifier."' AND version = '".$version."' AND groupid = 0";
} else {
	$pagelink = '?bundleidentifier='.$bundleidentifier.'&version='.$version.'&groupid='.$groupid;
	$whereclause = " WHERE groupid = ".$groupid;
}

show_header('- List');

$cols = '<colgroup><col width="20"/><col width="80"/><col width="140"/><col width="360"/><col width="300"/></colgroup>';

echo '<h2>';

if (!$acceptallapps)
	echo '<a href="app_name.php">Apps</a> - ';

echo create_link($bundleidentifier, 'app_versions.php', false, 'bundleidentifier').' - ';

if ($version != "")
    echo create_link('Version '.$version, 'groups.php', false, 'bundleidentifier,version').' - ';

if ($groupid != "") {
    echo create_link($groupid, 'crashes.php', false, $pagelink).'</h2>';
} else {
    echo create_link('Crashes', 'crashes.php', false, $pagelink).'</h2>';
}

if ($search != "" || $type != "")
    show_search($search, $type);

$osticks = "";
$osvalues = "";
$platformticks = "";

$crashestime = false;
$crashvaluesarray = array();
$crashvalues = "";

if ($groupid !='') {
    $cols2 = '<colgroup><col width="280"/><col width="340"/><col width="340"/></colgroup>';

    $query = "SELECT location, exception, reason, description FROM ".$dbgrouptable." WHERE id = '".$groupid."'";
    $result = mysqli_query($GLOBALS['link'], $query) or die(end_with_result('Error in SQL '.$query));

    $numrows = mysqli_num_rows($result);
    if ($numrows > 0) {
        // get the status
        while ($row = mysqli_fetch_row($result)) {
            $location = $row[0];
            $exception = $row[1];
            $reason = $row[2];
            $description = $row[3];
            
            $cols2 = '<colgroup><col width="316"/><col width="316"/><col width="315"/></colgroup>';
			echo '<table>'.$cols2.'<tr><th>Platform Overview</th><th>Crashes over time</th><th>System OS Overview</th></tr>';
			
			echo "<tr><td><div id=\"platformdiv\" style=\"height:280px;width:306px; \"></div></td>";
			echo "<td><div id=\"crashdiv\" style=\"height:280px;width:306px; \"></div></td>";
			echo "<td><div id=\"osdiv\" style=\"height:280px;width:305px; \"></div></td></tr></table>"; 
			
			// get the amount of crashes per system version
			$crashestime = true;
			
			$osticks = "";
			$osvalues = "";
			$query2 = "SELECT systemversion, COUNT(systemversion) FROM ".$dbcrashtable.$whereclause." group by systemversion order by systemversion desc";
			$result2 = mysqli_query($GLOBALS['link'], $query2) or die(end_with_result('Error in SQL '.$query2));
			$numrows2 = mysqli_num_rows($result2);
			if ($numrows2 > 0) {
				// get the status
				while ($row2 = mysqli_fetch_row($result2)) {
					if ($osticks != "") $osticks = $osticks.", ";
					$osticks .= "'".$row2[0]."'";
					if ($osvalues != "") $osvalues = $osvalues.", ";
					$osvalues .= $row2[1];
				}
			}
			mysqli_free_result($result2);
			
			// get the amount of crashes per system version
			$crashestime = true;
			
			$platformticks = "";
			$platformvalues = "";
			$query2 = "SELECT platform, COUNT(platform) FROM ".$dbcrashtable.$whereclause." AND platform != \"\" group by platform order by platform desc";
			$result2 = mysqli_query($GLOBALS['link'], $query2) or die(end_with_result('Error in SQL '.$query2));
			$numrows2 = mysqli_num_rows($result2);
			if ($numrows2 > 0) {
				// get the status
				while ($row2 = mysqli_fetch_row($result2)) {
					if ($platformticks != "") $platformticks = $platformticks.", ";
					$platformticks .= "'".$row2[0]."'";
					if ($platformvalues != "") $platformvalues = $platformvalues.", ";
					$platformvalues .= $row2[1];
				}
			}
			mysqli_free_result($result2);
			
			
			
			$cols2 = '<colgroup><col width="100"/><col width="850"/></colgroup>';
			echo '<table>'.$cols2.'<tr><th colspan="2">Group Details</th></tr>';
    		echo '<tr><td><b>Location:</b></td><td>'.$location.'</td></tr>';
    		echo '<tr><td><b>Exception:</b></td><td>'.$exception.'</td></tr>';
            echo '<tr><td><b>Reason:</b></td><td>'.$reason.'</td></tr>';
			echo '<tr><td><b>Description:</b></td><td>';
            echo '<form name="groupmetadata" action="" method="get">';
            echo '<textarea id="description'.$groupid.'" cols="100" rows="2" name="description" class="description" style="margin-left: 10px;width:700px">'.$description.'</textarea>';
            echo "<a href=\"javascript:updateGroupMeta(".$groupid.",'".$bundleidentifier."')\" class='button' style='float: right;'>Update</a>";
         	  echo create_issue($bundleidentifier, currentPageURL());
            echo '</form></td></tr></table>';
            
            // get the amount of crashes
            $amount = 0;
            $query2 = "SELECT count(*) FROM ".$dbcrashtable.$whereclause;
            $result2 = mysqli_query($GLOBALS['link'], $query2) or die(end_with_result('Error in SQL '.$query2));
            $numrows2 = mysqli_num_rows($result2);
            if ($numrows2 == 1) {
                $row2 = mysqli_fetch_row($result2);
                $amount = $row2[0];
            }
            mysqli_free_result($result2);
        }
    }
   	mysqli_free_result($result);
}

echo '<table id="crashlist" class="hover">'.$cols;
echo "<thead><tr><th>JB</th><th>System</th><th>Timestamp</th><th>User ID / Name / Email</th><th>Actions</th></tr></thead>";
echo '<tbody>';

// get all crashes
$query = "SELECT userid, username, contact, systemversion, timestamp, id, jailbreak, platform FROM ".$dbcrashtable.$whereclause." ORDER BY systemversion desc, timestamp desc";
$result = mysqli_query($GLOBALS['link'], $query) or die(end_with_result('Error in SQL '.$query));

$numrows = mysqli_num_rows($result);
if ($numrows > 0) {
	// get the status
	while ($row = mysqli_fetch_row($result)) {
		$userid = $row[0];
		$username = $row[1];
		$contact = $row[2];
		$systemversion = $row[3];
		$timestamp = $row[4];
		$crashid = $row[5];
		$jailbreak = $row[6];
		$platform = $row[7];
				
		$todo = 2;
		$query2 = "SELECT done FROM ".$dbsymbolicatetable." WHERE crashid = ".$crashid;
		$result2 = mysqli_query($GLOBALS['link'], $query2) or die(end_with_result('Error in SQL '.$query));

		$numrows2 = mysqli_num_rows($result2);
		if ($numrows2 > 0)
		{
			$row2 = mysqli_fetch_row($result2);
			$todo = $row2[0];
		}
		mysqli_free_result($result2);
		
		$now = time();
		
		if ($timestamp != "" && ($timestampvalue = strtotime($timestamp)) !== false)
		{
            $timeindex = substr($timestamp, 0, 10);

            if ($now - $timestampvalue < 60*24*24)
                $timestamp = "<font color='".$color24h."'>".$timestamp."</font>";
            else if ($now - $timestampvalue < 60*24*24*2)
                $timestamp = "<font color='".$color48h."'>".$timestamp."</font>";
            else if ($now - $timestampvalue < 60*24*24*3)
                $timestamp = "<font color='".$color72h."'>".$timestamp."</font>";
            else
                $timestamp = "<font color='".$colorOther."'>".$timestamp."</font>";
          
            // add the value to the chart stuff
      
            if (!array_key_exists($timeindex, $crashvaluesarray)) {
                $crashvaluesarray[$timeindex] = 0;
            }
            $crashvaluesarray[$timeindex]++;
		}

		echo "<tr id='crashrow".$crashid."' valign='top' align='center' data-url='javascript:showCrashID(".$crashid.")'>";
        
        echo "<td class='clickable'>";
		if ($jailbreak == 1) echo "x";
        echo "</td>";
		
        echo "<td class='clickable'>".$systemversion;
		if ($platform != "") echo "<br/>".$platform;
		echo "</td>";
		
        echo "<td class='clickable'>".$timestamp."</td>";
        
        echo "<td class='clickable'>".$userid."<br/>".$username."<br/>".$contact."</td>";
        
		echo "<td>";
		echo "<a href='actionapi.php?action=downloadcrashid&id=".$crashid."' class='button'>Download</a> ";
		echo "<span id='symbolicate".$crashid."'>";
		if ($todo != 0) {
    		echo "<a href='javascript:symbolicateCrashID(".$crashid.")' class='button'>";
    		if ($todo != 2)
                echo "Resymbolicate";
            else
                echo "Symbolicate";
    		echo "</a>";
        }
        echo "</span>";	
        echo " <a href='javascript:deleteCrashID(".$crashid.",";
        if ($groupid != "") {
            echo $groupid;
		} else {
            echo "-1";
		}
        echo ")' class='button redButton' onclick='return confirm(\"Do you really want to delete this item?\");'>Delete</a></td>";

		echo "</tr>";
	}
	
	mysqli_free_result($result);
} else {
	echo '<tr><td colspan="4">No data found</td></tr>';
}
echo '</tbody></table>';

echo "<table>".$cols;
echo "<tr><th colspan='2'>Description</th><th colspan='2'>Log</th></tr>";
echo "<tr><td colspan='2'><div id='descriptionarea' class='short'></div></td><td colspan='2'><div id='logarea' class='log'></div></td></tr></table>";

mysqli_close($link);

?>
<script type="text/javascript">
$(document).ready(function(){
    $("#crashlist").chromatable({
        width: "930px",
        height: "330px",
        scrolling: "yes"
    });
    $(".clickable").click(function() {
        row = $(this).parent();
        url = row.data("url");
        if (url != null) {
            window.document.location = url;
        }
    });

<?php 
  if ($platformticks != "") {
    include "jqplot.php";
  }
?>
});
</script>

</body></html>
