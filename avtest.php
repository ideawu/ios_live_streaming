<?php  
$url = "http://127.0.0.1:8100/stream";

$ch = curl_init($url);
curl_setopt($ch, CURLOPT_WRITEFUNCTION, 'myfunc');
$result = curl_exec($ch);
curl_close($ch);

function myfunc($ch, $data){
	$bytes = strlen($data);

	static $buf = '';
	$buf .= $data;
	while(1){
		$pos = strpos($buf, "\n");
		if($pos === false){
			break;
		}
		$data = substr($buf, 0, $pos+1);
		$buf = substr($buf, $pos+1);

		$resp = @json_decode($data, true);
		echo "strlen: " . strlen($data) . " seq: " . $resp['seq'] . "\n";
		if($resp['type'] == 'data'){
			$content = $resp['content'];
			$content = base64_decode($content);
			file_put_contents('a.txt', $content);
			die();
		}
	}

	return $bytes;
}

