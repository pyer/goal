module main

import hello

fn test_succeeds() {
    assert hello.hello() == 'Hello world !'
}

fn test_fails() {
    assert hello.hello() == 'Hello world'
}
