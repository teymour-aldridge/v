/*
	basic ftp module
	RFC-959
	https://tools.ietf.org/html/rfc959

	Methods:
	ftp.connect(host)
	ftp.login(user,passw)
	pwd := ftp.pwd()
	ftp.cd(folder)
	dtp := ftp.pasv()
	ftp.dir()
	ftp.get(file)
	dtp.read()
	dtp.close()
	ftp.close()
*/

module ftp

import net

const (
	Connected = 220
	SpecifyPassword = 331
	LoggedIn = 230
	LoginFirst = 503
	Anonymous = 530
	OpenDataConnection = 150
	CloseDataConnection = 226
	CommandOk = 200
	Denied = 550
	PassiveMode = 227
	Complete = 226
)

struct DTP {
mut:
	sock net.Socket
	ip string
	port int
}

fn (dtp DTP) read() []byte {
	mut data := []byte
	for {
		buf,len := dtp.sock.recv(1024)
		if len == 0 { break }

		for i:=0;i<len;i++ {
			data << buf[i]
		}
	}

	return data
}

fn (dtp DTP) close() {
	dtp.sock.close() or {}
}

struct FTP {
mut:
	sock net.Socket
	buffer_size int
}

pub fn new() FTP {
	mut f := FTP{}
	f.buffer_size = 1024
	return f
}

fn (ftp FTP) write(data string) ?int {
	$if debug {
		println('FTP.v >>> $data')
	}
	n := ftp.sock.send_string(data + '\n') or {
		return error('cannot send data')
	}
	return n
}

fn (ftp FTP) read() (int,string) {
	mut data := ftp.sock.read_line()
	$if debug {
		println('FTP.v <<< $data')
	}

	if data.len < 5 {
		return 0,''
	}

	code := data[0..3].int()
	if data[4] == `-` {
		for {
			data = ftp.sock.read_line()
			if data[0..3].int() == code {
				break
			}
		}
	}

	return code,data
}

pub fn (ftp mut FTP) connect(ip string) bool {
	sock := net.dial(ip, 21) or {
		return false
	}
	ftp.sock = sock

	code,_ := ftp.read()
	if code == Connected {
		return true
	}

	return false
}

pub fn (ftp FTP) login(user, passwd string) bool {

	ftp.write('USER '+user) or {
		println('ERROR sending user')
		return false
	}

	mut data := ''
	mut code := 0

	code,data = ftp.read()
	if code == LoggedIn {
		return true
	}

	if code != SpecifyPassword {
		return false
	}

	ftp.write('PASS '+passwd) or {
		println('ERROR sending password')
		return false
	}

	code,data = ftp.read()

	if code == LoggedIn {
		return true
	}

	return false
}

pub fn (ftp FTP) close() {
	send_quit := 'QUIT\r\n'
	ftp.sock.send_string(send_quit) or {}
	ftp.sock.close() or {}
}

pub fn (ftp FTP) pwd() string {
	ftp.write('PWD') or {
		return ''
	}
	_,data := ftp.read()
	spl := data.split('"')
	if spl.len >= 2 {
		return spl[1]
	}
	return data
}

pub fn (ftp FTP) cd(dir string) {
	ftp.write('CWD $dir') or { return }
	mut code, mut data := ftp.read()
	match code {
		Denied {
			println("CD $dir denied!")
		}
		Complete {
			code,data = ftp.read()
		}
		else {}
	}

	println('cd $data')
}

fn new_dtp(msg string) ?DTP {
	// it receives a control message 227 like: 
	// '227 Entering Passive Mode (209,132,183,61,48,218)'

	if !msg.contains('(') || !msg.contains(')') || !msg.contains(',') {
		return error('bad message')
	}

	t := msg.split('(')[1].split(')')[0].split(',')
	ip := t[0]+'.'+t[1]+'.'+t[2]+'.'+t[3]
	port := t[4].int()*256+t[5].int()

	sock := net.dial(ip, port) or {
		return error('Cant connect to the data channel')
	}

	dtp := DTP {
		sock : sock 
		ip: ip
		port: port
	}
	return dtp
}

fn (ftp FTP) pasv() ?DTP {
	ftp.write('PASV') or {}
	code,data := ftp.read()
	println("pass: $data")

	if code != PassiveMode {
		return error('pasive mode not allowed')
	}

	dtp := new_dtp(data)

	return dtp
}

pub fn (ftp FTP) dir() ?[]string {
	dtp := ftp.pasv() or {
		return error('cannot establish data connection')
	}

	ftp.write('LIST') or {}
	code,_ := ftp.read()
	if code == Denied {
		return error('list denied')
	}
	if code != OpenDataConnection {
		return error('data channel empty')
	}

	list_dir := dtp.read()
	result,_ := ftp.read()
	if result != CloseDataConnection {
		println('LIST not ok')
	}
	dtp.close()

	mut dir := []string
	sdir := string(byteptr(list_dir.data))
	for lfile in sdir.split('\n') {
		if lfile.len >1 {
			spl := lfile.split(' ')
			dir << spl[spl.len-1]
		}
	}

	return dir
}

pub fn (ftp FTP) get(file string) ?[]byte {
	dtp := ftp.pasv() or {
		return error('cant stablish data connection')
	}

	ftp.write('RETR $file') or {}
	code,_ := ftp.read()

	if code == Denied {
		return error('permission denied')
	}

	if code != OpenDataConnection {
		return error('data connection not ready')
	}

	blob := dtp.read()
	dtp.close()

	return blob
}