//
//  BLEPeripheral.swift
//  NAUExoControl
//
//  Created by Chancelor Frank Cuddeback on 5/27/20.
//  Copyright © 2020 Chancelor Frank Cuddeback. All rights reserved.
//

import UIKit
import CoreBluetooth

//make a delagate protocal to stop an error funtion.
protocol BLEDelegate {
    
}
//Make a peripheral class, that contains the UUIDs that were looking for
class BLEPeripheral: NSObject {
    public static let UARTService = CBUUID.init(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    public static let BLETXChar = CBUUID.init(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    public static let BLERXChar = CBUUID.init(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    public static let BLENameChar = CBUUID.init(string: "00002A00-0000-1000-8000-00805F9B34FB")
}

