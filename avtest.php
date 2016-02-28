<?php  
@unlink('a.mp4');
@unlink('a.json');

$url = "http://127.0.0.1:8100/stream?cname=";

$ch = curl_init($url);
curl_setopt($ch, CURLOPT_WRITEFUNCTION, 'myfunc');
$result = curl_exec($ch);
curl_close($ch);

function myfunc($ch, $data){
	static $next = 0;

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
		echo "strlen: " . strlen($data) . " type: {$resp['type']}, seq: " . $resp['seq'] . "\n";
		if($resp['type'] == 'data'){
			$content = $resp['content'];
			$content = base64_decode($content);
			/*
			if(ord($content) !== $next){
				echo "bad\n";
				die();
			}else{
				$next ++;
			}
			$content = ord($content) . "\n";
			*/
			file_put_contents('a.json', $data, FILE_APPEND);
			file_put_contents('a.mp4', $content, FILE_APPEND);
			die();
		}else if(in_array($resp['type'], array('noop', 'next_seq'))){
		}else{
			echo "bad resp\n";
		}
	}

	return $bytes;
}

