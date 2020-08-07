//
//  ViewController.swift
//  NAUExoControl
//
//  Created by Chancelor Frank Cuddeback on 5/8/20.
//  Copyright © 2020 Chancelor Frank Cuddeback. All rights reserved.
//The ViewController file is responsible for managing the Main.storyboard file and is the code associated with the GUI

//The UI elements currently include two text boxes capable of input, two buttons, a switch, a text box for display, a status light, and a graph. The body mass text box is referred to as massTextField/massTextOutlet. The other text fields are similar. The assist/resist toggle switch is referred to as assistResistSlider. The button that performs various Exo actions is surprisingly referred to as actionButton/actionButtonOutlet. The text field that is associated with the action button is creatively referred to as the actionTextField, this text field takes no inputs. The trial button is referred to as the trialButton/trialButtonOutlet. The status light at the upper left is referred to as the Status Image.

//UIKit has all of the GUI elements and classes that we need
import UIKit
//Core bluetooth provides all of the functions that we need to get connected
import CoreBluetooth
//Charts allows us to have ... a chart. Its a cocoapod.
import Charts
//Create an object of the ViewController class so that it may be referenced in other files, currently not in use
var VCObject = ViewController()
//Characteristics
var rxChar: CBCharacteristic?
var txChar: CBCharacteristic?
var nameChar: CBCharacteristic?
//Peripheral
var LEPeripheral: CBPeripheral!
//String var to store data buffer
var characteristicASCIIValue = String()


//Make a subclass of UIViewController
class ViewController: UIViewController , CBPeripheralDelegate, CBCentralManagerDelegate, UITextFieldDelegate, ChartViewDelegate {
    
    var timerFrequency: Double = 0.02
    
    //Initialize GUI Variables
    var bodyMass: String? = nil
    var trialActive: Bool = false
    var assistLevel: String? = nil
    var resistLevel: String? = nil
    var scanComplete: Bool = false
    var calibratedFSRS: Bool = false
    var calibratedTRQSRS: Bool = false
    var baselineTaken: Bool = false
    var connectComplete: Bool = false
    var actionState: String = "Not Pressed"
    var torqueActive: Bool = false
    
    //Initialize BLE Properties
    var centralManager: CBCentralManager!
    var tempRSSI = NSNumber()
    var minRequiredConnectionRSSI = NSNumber(45)
    var RSSIs = [NSNumber]()
    var data = NSMutableData()
    var intData = Data()
    var doubleData = Data()
    var charData = Data()
    var receivedData = Data()
    var RLTorque: [Double] = [0]
    var LLTorque: [Double] = [0]
    var peripherals: [CBPeripheral] = []
    var connectedPeripheral: CBPeripheral?
    var characteristicValue = [CBUUID: NSData]()
    var timer = Timer()
    var characteristics = [String : CBCharacteristic]()
    var BLEState: String = ""
    var chartData: [Data] = []
    let carriageReturnData = ("\r" as String).data(using: String.Encoding(rawValue: String.Encoding.ascii.rawValue))
    var beginParsingPayload = false
    var oldTrans = Data()
    var dataHandleCt = 0
    var gotMessageState: String = ""
    var messageCounter = 0
    
    //Init Chart Goodies
    let lineChart = LineChartView()
    var dataEntries = [ChartDataEntry]()
    var xAxisEntries = [Double]()
    var xLength: Double = 100
    var xAxisBuffer: Int = 0
    var chartIndex = 0
    var newData: Bool = false
    var commandData = Data()
    var lengthOfTransData = Data()
    
    @IBOutlet weak var actionTextField: UITextField!
    //Function to print to the text field
    func actionPrint(text: String) {
        actionTextField.text?.removeAll()
        actionTextField.insertText(text)
    }
    
    //GUI tie in for action button text
    @IBOutlet weak var actionButtonOutlet: UIButton!
    //Guit tie in for the trial button
    @IBOutlet weak var trialButtonOutlet: UIButton!
    //GUI tie in for mass text
    @IBOutlet weak var massTextOutlet: UITextField!
    //GUI tie in for Assist text
    @IBOutlet weak var assistTextOutlet: UITextField!
    //GUI tie in for connection status view
    @IBOutlet weak var statusImage: UIImageView!
    
    //Function that runs when the view loads
    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(lineChart)
        self.lineChart.delegate = self
        setupChartAndChartData()
        //The view loaded so make an instance of central manager
        centralManager = CBCentralManager(delegate: self, queue: nil) //Make an instance of the central
        
        massTextOutlet.delegate = self  //Make an instance of each text field
        assistTextOutlet.delegate = self
        //startTimer()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning() //Dispose of any resources that can be recreated
        print("Memory Warning")
    }
    
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Chart initializations, styling, and updating
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    
    func setupChartAndChartData() {
        lineChart.translatesAutoresizingMaskIntoConstraints = false
        lineChart.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        lineChart.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: CGFloat(150)).isActive = true
        lineChart.widthAnchor.constraint(equalToConstant: view.frame.width - 32).isActive = true
        lineChart.heightAnchor.constraint(equalToConstant: 300).isActive = true
        
        let chartDataSet: LineChartDataSet = LineChartDataSet(entries: [ChartDataEntry(x: Double(0), y: Double(0))], label: "Torque")
        chartDataSet.drawCirclesEnabled = false
        chartDataSet.setColor(NSUIColor.systemBlue)
        chartDataSet.mode = .cubicBezier
        lineChart.data = LineChartData(dataSet: chartDataSet)
        
        lineChart.xAxis.labelPosition = .bottom
        lineChart.xAxis.enabled = true
        lineChart.drawGridBackgroundEnabled = false
        lineChart.backgroundColor = UIColor.black
        lineChart.legend.enabled = true
        lineChart.isUserInteractionEnabled = false
    }
    
    @objc func updateChart() {
        lineChart.data?.addEntry(ChartDataEntry(x: Double(chartIndex), y: RLTorque[chartIndex]), dataSetIndex: 0)
        lineChart.setVisibleXRange(minXRange: Double(0), maxXRange: xLength)
        lineChart.notifyDataSetChanged()
        lineChart.moveViewToX(Double(chartIndex))
        chartIndex += 1
        
    }
    
    func clearChart() {
        xLength = 200
        lineChart.moveViewToX(0)
    }
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                    //Timer Functions
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /*func startTimer() {
        timer = Timer.scheduledTimer(timeInterval: timerFrequency, target: self, selector: #selector(updateChart), userInfo: nil, repeats: true)
        RunLoop.current.add(timer, forMode: .common)
    }
    
    func stopTimer() {
        timer.invalidate()
    } */
    
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                    //BLE Scanning, Connection, and Peripheral discovery Functions
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Function is called when local bluetooth modules changes state
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch (central.state) {
        case .poweredOn:
            BLEState = "On"
            print("BT Powered On")
            startScan()
        case .poweredOff:
            BLEState = "Off"
            statusImage.image = UIImage(named: "redcircle")
            actionPrint(text: "Check BT")
            print("BT Powered Off")
        case .unknown:
            BLEState = "Unknown"
            print("BT Unknown")
            statusImage.image = UIImage(named: "redcircle")
            actionPrint(text: "Check BT")
        case .resetting:
            BLEState = "Resetting"
            print("BT Resetting")
            statusImage.image = UIImage(named: "redcircle")
            actionPrint(text: "Check BT")
        case .unsupported:
            BLEState = "Unsupported"
            print("BT Unsupported")
            statusImage.image = UIImage(named: "redcircle")
            actionPrint(text: "Check BT")
        case .unauthorized:
            BLEState = "Unauthorized"
            print("BT Unauthorized")
            statusImage.image = UIImage(named: "redcircle")
            actionPrint(text: "Check BT")
        @unknown default:
            print("BT State Unknown")
            statusImage.image = UIImage(named: "redcircle")
            actionPrint(text: "Check BT")
            break
        }
    }
    
    //The function to begin looking for Peripherals
    func startScan() {
        if BLEState == "On" {
                actionPrint(text: "Scanning")
                print("Scanning...")
                //self.timer.invalidate()
                centralManager?.scanForPeripherals(withServices: [BLEPeripheral.UARTService], options: [CBCentralManagerScanOptionAllowDuplicatesKey:false])
        }
        else {
            print("Did not begin scanning ble state is \(BLEState)")
        }
    }
    
    //Function to stop scanning for peripherals
    func stopScan() {
         self.centralManager?.stopScan()
        scanComplete = true
        print("Scan Stoped")
    }

    //Function that handles when a peripheral is discoverd during scanning
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        //If the list of peripherals already contains the current element dont add it to the list
        if peripherals.contains(peripheral) {
            self.peripherals.append(peripheral)
        }
        print("Found \(peripherals.count) peripheral(s)!")
        self.RSSIs.append(RSSI)
        print(RSSIs)
        peripheral.delegate = self
        //peripheral.discoverServices([BLEPeripheral.UARTService])
        if LEPeripheral == nil {
            print("Peripheral Found")
            LEPeripheral = peripheral
            }
        if peripheral.name == "EXOBLE" /*&& checkRSSIFor(peripheral: peripheral).compare(minRequiredConnectionRSSI) == .orderedAscending*/ {
            connectToDevice(peripheral: peripheral)
            }
        }
    
    //Function to connect to a peripheral
    func connectToDevice (peripheral: CBPeripheral) {
        centralManager?.connect(peripheral, options: nil)
    }
    
    //Delagate that is called when a connection is made
     func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
         actionPrint(text: "Connected!")
         centralManager?.stopScan()
         //Erase data that may be in the buffer
         data.length = 0
         //Change status image
         statusImage.image = UIImage(named: "greencircle")
         connectComplete = true
         actionState = "Not Pressed"
         //Discovery Callback
         peripheral.delegate = self
         connectedPeripheral = peripheral
         //Only look for desired services
         peripheral.discoverServices([BLEPeripheral.UARTService])
     }
    
    //Delegate that is called when a peripheral is disconnected
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        statusImage.image = UIImage(named: "redcircle")
        scanComplete = false
        connectComplete = false
        calibratedFSRS = false
        calibratedTRQSRS = false
        actionState = "Not Pressed"
        actionButtonOutlet.setTitle("Calibrate FSRS", for: .normal)
        actionButtonOutlet.setTitleColor(UIColor.systemBlue, for: .normal)
        connectedPeripheral = nil
        disableTorque()
        startScan()
    }

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                    //Action Button functions and corresponding delegates
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    
    //Function that checks RSSI for a given peripheral (RSSI = Connection strength in decibel mW)
    func checkRSSI() {
        if connectComplete {
            connectedPeripheral!.readRSSI()
        }
    }
    
    //Delagate that is called to handle reading the RSSI of a peripheral
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if error != nil {
            print("RSSI Read Error: \(error!)")
            return
        }
        tempRSSI = RSSI
    }
    
    //Function to calibrate force sensitive resistors
    func calibrateFSR() {
        calibratedFSRS = true
        actionState = "Calibrated FSRS"
        sendData(data: "L")
        print("Calibrating FSRS!")
    }
    
    //Function to calibrate torque sensors
    func calibrateTRQSR() {
        calibratedTRQSRS = true
        actionState = "Calibrated TRQSRS"
        //sendData(data: "H")
        print("Calibrating Torque Sensors!")
    }
    //Function to take a baseline
    func takeBaseline() {
        baselineTaken = true
        actionState = "Taken Baseline"
        //sendData(data: "b")
        print("Taking Baseline!")
    }
    //Function to enable exo torque
    func enableTorque() {
        torqueActive = true
        //actionState = "Torque Enabled"
        sendData(data: "F")
        sendDouble(inputDouble: 2.4)
        sendDouble(inputDouble: 2.4)
        sendDouble(inputDouble: 2.4)
        sendDouble(inputDouble: 2.4)
        print("Torque activated!")
    }
    //Function to disable exo torque
    func disableTorque() {
        torqueActive = false
        //actionState = "Torque Disabled"
        sendData(data: "F")
        sendDouble(inputDouble: 0)
        sendDouble(inputDouble: 0)
        sendDouble(inputDouble: 0)
        sendDouble(inputDouble: 0)
        print("Torque deactivated!")
    }
    
    //Function to disconnect from device
    func disconnectFromDevice() {
        //Unconnect
        centralManager?.cancelPeripheralConnection(LEPeripheral!)
    }
    
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                    //Connected peripheral Discovery and Subscription
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //When services are discoverd this delegate is called
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if error != nil {
            print("DiscSerErr: \(error!.localizedDescription)")
            return
        }
        guard let services = peripheral.services else {
            print("Error referencing services: line 265")
            return
        }
        print("Service: \(services)")
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    //When characteristics are discoverd this delegate is called
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if error != nil {
            print("DiscCharErr: \(error!.localizedDescription)")
            return
        }
        guard let characteristics = service.characteristics else {
            print("Error referencing Characteristics: Line 281")
            return
        }
        
        print("Found \(characteristics.count) characteristics!")
        print("Characteristics found: \(characteristics)")
        
        for characteristic in characteristics {
            //looks for the right characteristic
            
            if characteristic.uuid.isEqual(BLEPeripheral.BLERXChar) {
                rxChar = characteristic
                
                //Once found, subscribe to the this particular characteristic...
                peripheral.setNotifyValue(true, for: rxChar!)
                print("RxChar ID: \(characteristic.uuid)")
            }
            if characteristic.uuid.isEqual(BLEPeripheral.BLETXChar) {
                txChar = characteristic
                print("TxChar ID: \(characteristic.uuid)")
            }
        }
    }

    //Function is called when subscribed characteristics update their value (i.e. we got a message on bluetooth)
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic == rxChar && error == nil {
            //Check if the characteristic value is non nil
            guard characteristic.value != nil else {
                return
            }
            //Reference the current characteristic data
            let currentData = characteristic.value!
            print(currentData as NSData)
            //Send the raw data buffer to be massaged, then constructed and handled
            //data flow: didUpdateValueFor -> massageData() -> constructMessage() -> gotMessage()
            massageData(dataIn: currentData)
        }
        else if characteristic != rxChar {
            print("Received val from unexpected characteristic")
        }
        else if error != nil {
            print("Error is: \(error!.localizedDescription)")
        }
        else {
            print("Unknown read state")
        }
    }
    
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                //Sending Functions
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    
    func sendDouble(inputDouble: Double) {
        let doubleBuffer = inputDouble
        //doubleData = Data(bytes: &doubleBuffer, count: 8)
        //doubleData = Data(buffer: UnsafeBufferPointer(start: &doubleBuffer, count: 1))
        doubleData = withUnsafeBytes(of: doubleBuffer) { Data($0) }
        if let LEPeripheral = LEPeripheral {
            LEPeripheral.writeValue(doubleData, for: txChar!, type: CBCharacteristicWriteType.withoutResponse)
        }
    }
    
    func sendData(data: String) {
        let valueString = (data as String).data(using: String.Encoding(rawValue: String.Encoding.ascii.rawValue)) //Encoding.utf8.rawValue
        if let LEPeripheral = LEPeripheral {
            if txChar != nil {
                LEPeripheral.writeValue(valueString!, for: txChar!, type: CBCharacteristicWriteType.withoutResponse)
            }
            else {
                print("txChar Not Yet Found!")
            }
        }
    }
    //Function that is called when data is sent
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            print("SendErr: \(error!.localizedDescription)")
            return
        }
        print("Send Success")
    }
    
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Receiving functions
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    
    //Rub up on the data. Get it all relaxed so you can "talk" to it. No but actually, this function parses through [Data] looking for the new line character, makes a new 'message', and adds that message to a return array of data buffers.
    //Variables for massageData()
    var trailingData = Data()
    let newLineData = ("\n" as String).data(using: String.Encoding(rawValue: String.Encoding.ascii.rawValue))
    //So it seperates messages that are incorrectly placed into the same buffer
    func massageData(dataIn: Data) {

        //Make a mutable reference of data, (you can change its stored value)
        var dataRef = dataIn
        var nlIndexArray = [Int]()
        var message = [Data]()
        
        if !trailingData.isEmpty {
            dataRef.insert(contentsOf: trailingData, at: 0)
            //Empty trailingData
            trailingData.removeAll()
        }
        //Check if the previous dataBuffer had leftover unused data
        //Is \n is in the buffer
        if dataRef.contains(newLineData!.bytes[0]) {
            //Iterate through each element in the buffer
            var counter = 0
            for byte in dataRef {
                //If the current index is equal to \n
                if byte == newLineData!.bytes[0] {
                    nlIndexArray.append(counter)
                }
                counter += 1
            }
            //Construct messages
            for i in 0 ... nlIndexArray.count - 1 {
                if i == 0 {
                    message.append(dataRef.subdata(in: 0 ..< nlIndexArray[i] + 1))
                }
                else {
                    message.append(dataRef.subdata(in: nlIndexArray[i - 1] + 1 ..< nlIndexArray[i] + 1))
                }
            }
            //Remove the data that was added to the return message
            dataRef.removeSubrange(0 ..< dataRef.lastIndex(of: newLineData!.bytes[0])! + 1)
            //Check if there is any data left
            if !dataRef.isEmpty {
                //Add the leftover data to a buffer that will be used in a future call
                trailingData.append(dataRef)
                //Send the data that was successfully handled
                let returnMessage = choppyChop(data: message)
                message.removeAll()
                constructMessage(dataIn: returnMessage)
            }
                //Runs if dataRef is empty
            else {
                let returnMessage = choppyChop(data: message)
                message.removeAll()
                constructMessage(dataIn: returnMessage)
            }
        }
        else {
            //The data does not contain the newline character
            trailingData.append(dataRef)
        }
    }
    
    //Variables for the construct message function
    var leftOverData: [Data]? = nil
    var doublePayload = [Double]()
    var dataLength: Int? = nil
    var commandString: String? = nil
    var workingOnIt = false
    var startIndex: Int? = nil
    let startFlagData = "S".data(using: .utf8)!
    
    //This function forms the massaged data into an actual message
    func constructMessage(dataIn: [Data]) {
        //you've seen this before folks, were makin' a mutable reference of dataIn
        var dataRef = dataIn
        var startIndexArray: [Int] = []
        
        if leftOverData != nil {
            leftOverData!.append(contentsOf: dataIn)
            dataRef = leftOverData!
            leftOverData = nil
        }
        
        //iterate through dataRef and find the startFlag
        var forEachCounter = 0
        dataRef.forEach { message in
            if message == startFlagData {
                startIndexArray.append(forEachCounter)
            }
            forEachCounter += 1
        }
        
        guard startIndexArray.count != 0 else {
            //This means that startIndexArray was never populated so a reference of the data should be saved, this function will be called again when new data arrives
            leftOverData = dataRef
            return
        }
        //Used to iterate throught the startIndexArray
        for startIndex in startIndexArray {
            //Called when at the last startFlag
            if startIndex == startIndexArray.last! {
                for i in startIndex ... dataRef.count - 1 {
                    //Called when at the last startFlag and the last index
                    if i == dataRef.count - 1 {
                        if commandString == nil && dataRef[i].type() == "String" && dataRef[i] != startFlagData {
                            commandString = String(data: dataRef[i], encoding: .utf8)!
                        }
                        else if dataLength == nil && dataRef[i].type() == "Int" {
                            dataLength = Int(String(data: dataRef[i], encoding: .utf8)!)!
                        }
                        else if dataRef[i].type() == "Double" && Double(String(data: dataRef[i], encoding: .utf8)!)! != doublePayload.last {
                            doublePayload.append(Double(String(data: dataRef[i], encoding: .utf8)!)!)
                            if doublePayload.count == dataLength {
                                gotMessage(command: commandString!, data: doublePayload)
                                commandString = nil
                                dataLength = nil
                                doublePayload.removeAll()
                                return
                            }
                            else {
                                //Create the leftOverData
                                var leftOverBuffer = [Data]()
                                for index in startIndex ... dataRef.count - 1 {
                                    leftOverBuffer.append(dataRef[index])
                                }
                                leftOverData = leftOverBuffer
                                leftOverBuffer.removeAll()
                                doublePayload.removeAll()
                                return
                            }
                        }
                        else {
                            print("Making leftOverData")
                            //Create the leftOverData
                            var leftOverBuffer = [Data]()
                            doublePayload.removeAll()
                            for index in startIndex ... dataRef.count - 1 {
                                leftOverBuffer.append(dataRef[index])
                            }
                            leftOverData = leftOverBuffer
                            leftOverBuffer.removeAll()
                            return
                        }
                    }
                //Called when at the last startflag but not the last index
                else {
                        if commandString == nil && dataRef[i + 1].type() == "String" {
                        commandString = String(data: dataRef[i + 1], encoding: .utf8)!
                    }
                    else if dataLength == nil && dataRef[i + 1].type() == "Int" {
                        dataLength = Int(String(data: dataRef[i + 1], encoding: .utf8)!)!
                    }
                    else if dataRef[i + 1].type() == "Double" {
                        doublePayload.append(Double(String(data: dataRef[i + 1], encoding: .utf8)!)!)
                        if doublePayload.count == dataLength {
                            //We made a complete message!!!
                            gotMessage(command: commandString!, data: doublePayload)
                            commandString = nil
                            dataLength = nil
                            doublePayload.removeAll()
                            return
                        }
                    }
                }
            }
        }
        //Called when normally iterating through array (i.e. not at the last startFlag)
        else {
            commandString = String(data: dataRef[startIndex + 1], encoding: .utf8)!
                print(String(data: dataRef[startIndex + 2], encoding: .utf8)!)
            dataLength = Int(String(data: dataRef[startIndex + 2], encoding: .utf8)!)!
            for i in 1 ... dataLength! {
                doublePayload.append(Double(String(data: dataRef[startIndex + 2 + i], encoding: .utf8)!)!)
            }
            gotMessage(command: commandString!, data: doublePayload)
            commandString = nil
            dataLength = nil
            doublePayload.removeAll()
            }
        }
    }
    
    func choppyChop(data: [Data]) -> [Data]{
        var dataRef = data
        var counter = 0
        for index in 0 ... dataRef.count - 1 {
            dataRef[index].removeLast()
            dataRef[index].removeLast()
            counter += 1
        }
        return dataRef
    }
    
    //Called when a complete message has been created
    func gotMessage(command: String, data: [Double] ) {
        print(command)
        print(data)
        switch command {
        case "?":
            //Update chart with torque
                RLTorque.append(data[0])
                updateChart()
                LLTorque.append(data[1])
                updateChart()
            
        default:
            print("Received Command: \(command)")
        }
    }
    
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Begin IBAction declarations/methods this are called when their respective UI elements change state
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    
    //Function that makes the text fields return key... return
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        massTextOutlet.resignFirstResponder()
        assistTextOutlet.resignFirstResponder()
        return true
    }
    //GUI function for desired assistance
    @IBAction func assistTextField(_ sender: Any) {
        //Text field is done editing
        if let assistLevel = Double(assistTextOutlet.text!) {
            print("Assist level is: \(assistLevel)")
        }
        else {
            print("Invalid text Field input")
        }
    }
    
    //GUI function for assist/ressist slider
    @IBAction func assistResistSlider(_ sender: Any) {
    }
    
    //GUI function for mass text field
    @IBAction func massTextField(_ sender: Any) {
        //Editing text field is done
        //Set var bodyMass equal to value
        if let bodyMass = Double(massTextOutlet.text!) {
                   print("Body Mass is: \(bodyMass)")
               }
               else {
                   print("Invalid text Field input")
               }
    }
    //GUI function for action button
    @IBAction func actionButton(_ sender: Any) {
        //Button is pressed
        //Switch Case dictating the state of the action button
        if connectComplete && BLEState == "On" {
            switch actionState {
            case "Not Pressed":
                actionPrint(text: "Calibrating")
                calibrateFSR()
                actionButtonOutlet.setTitle("Calibrate TQSR", for: .normal)
            case "Calibrated FSRS":
                actionPrint(text: "Calibrating")
                calibrateTRQSR()
                actionButtonOutlet.setTitle("Take BaseLine", for: .normal)
                actionButtonOutlet.setTitleColor(UIColor.green, for: .normal)
            case "Calibrated TRQSRS":
                actionPrint(text: "Getting Her Done")
                takeBaseline()
                actionButtonOutlet.setTitle("Check RSSI", for: .normal)
                actionButtonOutlet.setTitleColor(UIColor.gray, for: .normal)
            case "Taken Baseline":
                actionTextField.text?.removeAll()
                //CheckRSSI() updates the tempRSSI variable
                checkRSSI()
                actionTextField.insertText("RSSI: \(tempRSSI)")
            default:
                print(actionState)
                actionTextField.text?.removeAll()
                actionTextField.insertText("State Error")
            }
        }
        else {
            actionPrint(text: "Check BT")
            print("Not Connected or BTState not on")
        }
    }
    //GUI funtion for trial button
    @IBAction func trialButton(_ sender: Any) {
        //Button is pressed
        //Change title to stop trial
        if connectComplete && BLEState == "On" {
            if !trialActive {
                trialButtonOutlet.setTitle("Stop Trial", for: .normal)
                //Change title color to red
                trialButtonOutlet.setTitleColor(UIColor.red, for: .normal)
                //Change state variable
                trialActive = true
                sendData(data: "D")
                //enableTorque()
                //sendData(data: "E")
                print("Trial Started")
            }
            //Change back if clicked again
            else if trialActive {
                //Change title to start trial
                trialButtonOutlet.setTitle("Start Trial", for: .normal)
                //Change title color to green
                trialButtonOutlet.setTitleColor(UIColor.green, for: .normal)
                //Change state variable
                trialActive = false
                //sendDouble(inputDouble: 0)
                disableTorque()
                print("Trial Stopped")
            }
        }
        else {
            actionPrint(text: "Check BT")
            print("Not Connected or BTState not on")
        }
    }
}

//Extension for Data -> UInt8 Byte array and adds a "type()" method to the Data class.
//The type method is used for safe unwrapping when decoding the incoming data buffer
extension Data {
    var bytes: [UInt8] {
        return [UInt8](self)
    }
    func type() -> String {
        if String(data: self, encoding: .utf8) != nil {
            let string = String(data: self, encoding: .utf8)
            if Int(string!) != nil {
                return "Int"
            }
            else if Double(string!) != nil {
                return "Double"
            }
            return "String"
        }
        return "nil"
    }
}

//Extension for UInt8 Byte array -> Data
extension Array where Element == UInt8 {
    var data: Data {
        return Data(self)
    }
}

