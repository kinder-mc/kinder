/*
################################################################################
#  THIS FILE IS 100% GENERATED BY ZPROJECT; DO NOT EDIT EXCEPT EXPERIMENTALLY  #
#  Please refer to the README for information about making permanent changes.  #
################################################################################
*/

#include "QmlZstr.h"



QObject* QmlZstr::qmlAttachedProperties(QObject* object) {
    return new QmlZstrAttached(object);
}


///
//  Receive C string from socket. Caller must free returned string using
//  zstr_free(). Returns NULL if the context is being terminated or the 
//  process was interrupted.                                            
QString QmlZstrAttached::recv (void *source) {
    char *retStr_ = zstr_recv (source);
    QString retQStr_ = QString (retStr_);
    free (retStr_);
    return retQStr_;
};

///
//  Receive a series of strings (until NULL) from multipart data.    
//  Each string is allocated and filled with string data; if there   
//  are not enough frames, unallocated strings are set to NULL.      
//  Returns -1 if the message could not be read, else returns the    
//  number of strings filled, zero or more. Free each returned string
//  using zstr_free(). If not enough strings are provided, remaining 
//  multipart frames in the message are dropped.                     
int QmlZstrAttached::recvx (void *source, QString stringP) {
    return zstr_recvx (source, stringP.toUtf8().data());
};

///
//  Send a C string to a socket, as a frame. The string is sent without 
//  trailing null byte; to read this you can use zstr_recv, or a similar
//  method that adds a null terminator on the received string. String   
//  may be NULL, which is sent as "".                                   
int QmlZstrAttached::send (void *dest, const QString &string) {
    return zstr_send (dest, string.toUtf8().data());
};

///
//  Send a C string to a socket, as zstr_send(), with a MORE flag, so that
//  you can send further strings in the same multi-part message.          
int QmlZstrAttached::sendm (void *dest, const QString &string) {
    return zstr_sendm (dest, string.toUtf8().data());
};

///
//  Send a formatted string to a socket. Note that you should NOT use
//  user-supplied strings in the format (they may contain '%' which  
//  will create security holes).                                     
int QmlZstrAttached::sendf (void *dest, const QString &format) {
    return zstr_sendf (dest, "%s", format.toUtf8().data());
};

///
//  Send a formatted string to a socket, as for zstr_sendf(), with a      
//  MORE flag, so that you can send further strings in the same multi-part
//  message.                                                              
int QmlZstrAttached::sendfm (void *dest, const QString &format) {
    return zstr_sendfm (dest, "%s", format.toUtf8().data());
};

///
//  Send a series of strings (until NULL) as multipart data   
//  Returns 0 if the strings could be sent OK, or -1 on error.
int QmlZstrAttached::sendx (void *dest, const QString &string) {
    return zstr_sendx (dest, string.toUtf8().data());
};

///
//  Accepts a void pointer and returns a fresh character string. If source
//  is null, returns an empty string.                                     
QString QmlZstrAttached::str (void *source) {
    char *retStr_ = zstr_str (source);
    QString retQStr_ = QString (retStr_);
    free (retStr_);
    return retQStr_;
};

///
//  Free a provided string, and nullify the parent pointer. Safe to call on
//  a null pointer.                                                        
void QmlZstrAttached::free (QString stringP) {
    zstr_free (stringP.toUtf8().data());
};

///
//  Self test of this class.
void QmlZstrAttached::test (bool verbose) {
    zstr_test (verbose);
};

/*
################################################################################
#  THIS FILE IS 100% GENERATED BY ZPROJECT; DO NOT EDIT EXCEPT EXPERIMENTALLY  #
#  Please refer to the README for information about making permanent changes.  #
################################################################################
*/
