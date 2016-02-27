<?php
$url = "http://127.0.0.1:8000/push";
$dir = "/var/folders/fw/y8gs_wys7_n5_f_yb4y7mg2m0000gn/T/";
for($i=0; $i<5; $i++){
	$file = sprintf("m%03d.mp4", $i);
	$file = "$dir/$file";
	$content = file_get_contents($file);
	$content = base64_encode($content);
	$data = array(
		'content' => $content,
	);
	$ret = http_post($url, $data);
	echo $ret;
}


function http_post($url, $data){
	if(is_array($data)){
		$data = http_build_query($data);
	}
	$ch = curl_init($url) ;
	curl_setopt($ch, CURLOPT_POST, 1) ;
	curl_setopt($ch, CURLOPT_POSTFIELDS, $data);
	curl_setopt($ch, CURLOPT_HEADER, 0);
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1) ;
	curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
	$result = @curl_exec($ch) ;
	curl_close($ch) ;
	return $result;
}

