#!/usr/local/bin/python2.7
# encoding: utf-8
# -*- coding: utf-8 -*-
'''
Created on Jan 9, 2023

@author: rag
'''
import sys
import os
# Append local libs
sys.path.append(os.path.dirname(os.path.realpath(sys.argv[0]))+ os.sep +"libs")
import re
import json
import logging

__debug_traceback__ = False
DEBUG = 1
ERROR_CODE = 0

if DEBUG == 1:
    __debug_traceback__ = True

if __debug_traceback__:
    # traceback - used for tracing exceptions
    import traceback
    import time

def we_are_frozen():
    """
    Returns whether we are frozen via py2exe.
    This will affect how we find out where we are located.
    """

    return hasattr(sys, "frozen")

def module_path():
    """ This will get us the program's directory,
    even if we are frozen using py2exe"""

    if we_are_frozen():
        return os.path.realpath(os.path.dirname(unicode(sys.executable, sys.getfilesystemencoding( ))))

    return os.path.realpath(os.path.dirname(unicode(__file__, sys.getfilesystemencoding( ))))


def init_settings():
    global SCRIPT_PATH, PROGRAM_NAME, TOOL_NAME, LOG_FILE_PATH, TOOL_CONFIG, FILE_EXTENSION_CHECKLISTS, LOG_LEVEL
    global COLLAB_ADMIN_USER, COLLAB_ADMIN_TOKEN, COLLAB_REVIEW_ID, COLLAB_API_URL
    
    
    SCRIPT_PATH = module_path()
    PROGRAM_NAME = os.path.basename(sys.argv[0])
    TOOL_NAME = os.path.splitext(PROGRAM_NAME)[0]
    LOG_FILE_PATH = os.path.normpath(SCRIPT_PATH + os.sep +  TOOL_NAME + '.log')
    TOOL_CONFIG = TOOL_NAME+"_config"
    TOOL_CONFIG = __import__(TOOL_CONFIG)
    
    FILE_EXTENSION_CHECKLISTS = TOOL_CONFIG.FILE_EXTENSION_CHECKLISTS
    
    LOG_LEVEL = TOOL_CONFIG.LOG_LEVEL
    
    COLLAB_API_URL          = os.environ.get('COLLAB_review.api_url', 'http://127.0.0.1:1003/services/json/v1')
    COLLAB_ADMIN_USER       = os.environ.get('COLLAB_review.admin_user', 'rag')
    COLLAB_ADMIN_TOKEN      = os.environ.get('COLLAB_review.admin_token', 'aaf83010ce6de300108463800952f421')
    
    COLLAB_REVIEW_ID        = os.environ.get('COLLAB_review.id', '500')  # ${review.id} in the collaborator session
    
def init_logger():
    if DEBUG:
        print("Initialize log file %s" % LOG_FILE_PATH)  # Corrected for Python 3
    logging.basicConfig(format='%(asctime)s %(funcName)s [%(levelname)s]: %(message)s',
                        datefmt='%Y-%m-%d %H:%M:%S',
                        filename=LOG_FILE_PATH,
                        level=LOG_LEVEL)
        

def addChecklist(checklists):
    
    logging.info("Adding checklists %s to review %s" % (checklists, COLLAB_REVIEW_ID))
    headers = {
      'Content-Type': 'application/json'
    }
    
    json_payload = [{
        "command": "SessionService.authenticate",
        "args": {
          "login": COLLAB_ADMIN_USER,
          "ticket": COLLAB_ADMIN_TOKEN
        }
      }]
    
    for checklistId in checklists:
        json_payload.append({
        "command": "ReviewService.addChecklist",
        "args": {
          "reviewId": COLLAB_REVIEW_ID,
          "checklistId": checklistId,
        }
      })
        
    
    
    payload = json.dumps(json_payload)
    
    r = requests.request("POST", COLLAB_API_URL, headers=headers, data=payload)
    COCO_INFO = r.json()
    
    if(DEBUG):
        print(json.dumps(COCO_INFO, indent=2))
        
    
    if ("errors" in COCO_INFO[0]):
        ERROR_STR = 'An error occurred while trying to log in into CoCo JSON API: "%s"' % ( COCO_INFO[0])
        logging.warning(ERROR_STR)
        
    for json_info in COCO_INFO[1:]:
        if ("errors" in json_info):
            ERROR_STR = 'An error occurred while trying to addChecklist on review %s: "%s"' % (COLLAB_REVIEW_ID, json_info)
            logging.warning(ERROR_STR)
    

def addedFiles():
    headers = {
      'Content-Type': 'application/json'
    }
    
    payload = json.dumps([
      {
        "command": "SessionService.authenticate",
        "args": {
          "login": COLLAB_ADMIN_USER,
          "ticket": COLLAB_ADMIN_TOKEN
        }
      },
      {
        "command": "ReviewService.getReviewSummary", # slow but we need also the list of active checklist to prevent duplicationg checklist items
#         "command": "ReviewService.getReviewMaterials", # fast
        "args": {
          "reviewId": COLLAB_REVIEW_ID,
          "clientBuild": 14000,
          "active": True
        }
      }
    ])
    
    r = requests.request("POST", COLLAB_API_URL, headers=headers, data=payload)
    
    json_data = r.json()
 
    # extract review materials
    review_data = json_data[1]
    scmMaterials = review_data['result']['scmMaterials']
    
#     if(DEBUG):
#         print(json.dumps(scmMaterials, indent=2))
    
    active_checklists = []
    
    for reviewChecklist in review_data['result']['reviewChecklists']:
        active_checklists.append(reviewChecklist['id'])
    
    
    checklists_to_be_added = []
    
    for scmMaterial in scmMaterials:
#         print(json.dumps(scmMaterial, indent=2)) 
        
        for reviewSummaryFile in scmMaterial['consolidatedChangelist']['reviewSummaryFiles']:
#             print(json.dumps(reviewSummaryFile, indent=2)) 
            
            for validation_rule in FILE_EXTENSION_CHECKLISTS:
                if(re.match(validation_rule['validation'], reviewSummaryFile['path'], re.IGNORECASE)):
                    checklists_to_be_added = set(checklists_to_be_added)  # Remove any duplicates before adding
                    checklists_to_be_added.update(validation_rule['checklistids'])  # Add new checklist IDs
    
    # remove checklist id's which are already active on review
    for checklict_id in active_checklists:
        if checklict_id in checklists_to_be_added:
            logging.info('Checklist %s already active on review, skipping' % checklict_id)
            checklists_to_be_added.remove(checklict_id)
        
    print ("Checklists to be added:")
    print (checklists_to_be_added)
    
    if(len(checklists_to_be_added) > 0):
        addChecklist(checklists_to_be_added)

    
if __name__ == '__main__':
    #===============================================================================
    # Profiler
    #===============================================================================
    if __debug_traceback__:
        clk = time.clock()
        tme = time.time()
    
    
    
    # Initialize the default error code(0 = ok, 1 = error)
    
    
    
    try:
        #--------------------------------------------------------------------------------
        # Step 1. Initialization
        #--------------------------------------------------------------------------------
        init_settings()
        
        init_logger()
        logging.info('Start')
        
        #--------------------------------------------------------------------------------
        # Step 2. Validation
        #--------------------------------------------------------------------------------
        if(os.environ.get('COLLAB_review.workflow', '') == ''):
            ERROR_CODE = 100
            ERROR_STR = 'No trigger dispatcher environment detected! Please call this script whit all arguments provided by Trigger Dispatcher'
            print >> sys.stderr, ERROR_STR
            sys.exit(ERROR_CODE)
        
        # apply custom logic only to soecific templates
        if( re.match(TOOL_CONFIG.TEMPLATE_VALIDATION , os.environ.get('COLLAB_review.workflow', '') ) is not None):
            logging.info('Detected template %s, starting monitoring uploaded files' % os.environ.get('COLLAB_review.workflow', ''))
            addedFiles()
        else:
            logging.info('Skip monitoring uploaded files')
        logging.info('STOP')
    except SystemExit:
        # Catch the SystemExit exceptions and treat them separately as they do not usually
        #    indicate an error
        # (we may get here from the argparse generated SystemExit exception)
        pass
    
    except:
        # We should never get here, but log everything if this is the case
        ERROR_CODE = 100
        ERROR_STR = 'An internal error occurred. Please contact the application developers and ' \
            'provide the following information: %s %s @[%s]' % (sys.exc_info()[0], sys.exc_info()[1], 'E000')
            
        if __debug_traceback__ :
            traceback.print_exc(file=sys.stderr)
        print >> sys.stderr, ERROR_STR
    
    if __debug_traceback__:
        print("=" * 79 + "\nTime Profiler\n" + "-" * 79)
        print("Clock = %f seconds" % (time.clock() - clk))
        print("Time  = %f seconds" % (time.time() - tme))
        print("=" * 79)
    # Exit and return the ERROR_CODE 
    sys.exit(ERROR_CODE)
    