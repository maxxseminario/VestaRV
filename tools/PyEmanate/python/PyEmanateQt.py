# -*- coding: utf-8 -*-

# Form implementation generated from reading ui file 'qt\PyEmanateQt.ui'
#
# Created by: PyQt5 UI code generator 5.13.2
#
# WARNING! All changes made in this file will be lost!


from PyQt5 import QtCore, QtGui, QtWidgets


class Ui_MainWindow(object):
    def setupUi(self, MainWindow):
        MainWindow.setObjectName("MainWindow")
        MainWindow.resize(800, 600)
        self.centralwidget = QtWidgets.QWidget(MainWindow)
        self.centralwidget.setObjectName("centralwidget")
        self.groupBoxSerialPorts = QtWidgets.QGroupBox(self.centralwidget)
        self.groupBoxSerialPorts.setGeometry(QtCore.QRect(10, 10, 121, 181))
        self.groupBoxSerialPorts.setObjectName("groupBoxSerialPorts")
        self.listView = QtWidgets.QListView(self.groupBoxSerialPorts)
        self.listView.setGeometry(QtCore.QRect(10, 20, 101, 111))
        self.listView.setObjectName("listView")
        self.pushButtonRefreshComList = QtWidgets.QPushButton(self.groupBoxSerialPorts)
        self.pushButtonRefreshComList.setGeometry(QtCore.QRect(10, 140, 101, 31))
        self.pushButtonRefreshComList.setObjectName("pushButtonRefreshComList")
        MainWindow.setCentralWidget(self.centralwidget)

        self.retranslateUi(MainWindow)
        QtCore.QMetaObject.connectSlotsByName(MainWindow)

    def retranslateUi(self, MainWindow):
        _translate = QtCore.QCoreApplication.translate
        MainWindow.setWindowTitle(_translate("MainWindow", "PyEmanate"))
        self.groupBoxSerialPorts.setTitle(_translate("MainWindow", "Serial Ports"))
        self.pushButtonRefreshComList.setToolTip(_translate("MainWindow", "<html><head/><body><p>Refresh the list of available serial ports</p></body></html>"))
        self.pushButtonRefreshComList.setText(_translate("MainWindow", "Refresh"))


if __name__ == "__main__":
    import sys
    app = QtWidgets.QApplication(sys.argv)
    MainWindow = QtWidgets.QMainWindow()
    ui = Ui_MainWindow()
    ui.setupUi(MainWindow)
    MainWindow.show()
    sys.exit(app.exec_())
