//
//  RootVC.swift
//  Internet Map
//
//  Created by Nigel Brooke on 2017-11-16.
//  Copyright © 2017 Peer1. All rights reserved.
//

import UIKit
import ARKit

private class CameraDelegate: NSObject, ARSessionDelegate {
    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        print(frame.camera.transform.columns.3)
    }
}

public class RootVC: UIViewController {
    private var rendererVC: ViewController!
    private var arkitView: ARSCNView!
    private var cameraDelegate = CameraDelegate()

   public override func viewDidLoad() {
        super.viewDidLoad()

        arkitView = ARSCNView()
        arkitView.frame = view.frame
        view.addSubview(arkitView)

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        arkitView.session.run(configuration)

        arkitView.session.delegate = cameraDelegate

        if UIDevice.current.userInterfaceIdiom == .phone {
            rendererVC = ViewController(nibName: "ViewController_iPhone", bundle: nil)
        }
        else {
            rendererVC = ViewController(nibName: "ViewController_iPad", bundle: nil)
        }

        rendererVC.view.frame = view.frame
        view.addSubview(rendererVC.view)
        addChildViewController(rendererVC)


        // Do any additional setup after loading the view.
    }
}
